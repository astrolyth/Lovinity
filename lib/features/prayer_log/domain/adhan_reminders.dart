import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/time/prayer_engine.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../settings/domain/settings_providers.dart';

const _days = 7; // 35 alerts, well under iOS's 64 pending-notification cap.
const _baseId = 7000;
const _arabic = {
  Prayer.fajr: 'الفجر',
  Prayer.dhuhr: 'الظهر',
  Prayer.asr: 'العصر',
  Prayer.maghrib: 'المغرب',
  Prayer.isha: 'العشاء',
};

/// The reminders to schedule: every prayer still ahead of [now], with a
/// stable id per (day offset, prayer) so a reschedule overwrites in place.
List<(int, ScheduledPrayer)> adhanSlots(
  List<List<ScheduledPrayer>> days,
  DateTime now,
) => [
  for (final (d, day) in days.indexed)
    for (final p in day)
      if (p.at.isAfter(now)) (_baseId + d * 5 + p.prayer.index, p),
];

/// Keeps the next week of adhan reminders scheduled. Reschedules when the
/// setting, location, method or day changes; clears them while the wife's
/// period is active (her prayers are excused). Watched once from HomeScreen.
final adhanReminderSchedulerProvider = Provider<void>((ref) {
  final on = ref.watch(adhanRemindersProvider);
  final profile = ref.watch(ownProfileProvider).asData?.value;
  final resting =
      profile?.gender == 'female' && ref.watch(activeCycleProvider) != null;
  ref.watch(todayKeyProvider);
  final push = ref.read(pushServiceProvider);

  final lat = profile?.latitude, lon = profile?.longitude;
  final days = !on || resting || lat == null || lon == null
      ? const <List<ScheduledPrayer>>[]
      : [
          for (var d = 0; d < _days; d++)
            prayerTimesForDay(
              date: DateTime.now().add(Duration(days: d)),
              loc: PrayerLocation(
                latitude: lat,
                longitude: lon,
                timezone: profile!.timezone,
              ),
              config: PrayerConfig(
                madhab: profile.madhhab == 'hanafi'
                    ? Madhab.hanafi
                    : Madhab.shafi,
                method: calcMethodFromDb(profile.calcMethod),
              ),
            ),
        ];
  unawaited(_reschedule(push.available, adhanSlots(days, DateTime.now())));
});

Future<void> _reschedule(
  bool pushReady,
  List<(int, ScheduledPrayer)> slots,
) async {
  final plugin = FlutterLocalNotificationsPlugin();
  try {
    // PushService sets the plugin up only when Firebase is configured; the
    // reminders are local, so they must work without it.
    if (!pushReady) {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
    }
    for (var id = _baseId; id < _baseId + _days * 5; id++) {
      await plugin.cancel(id: id);
    }
    for (final (id, p) in slots) {
      await plugin.zonedSchedule(
        id: id,
        title: '${p.prayer.displayName} · ${_arabic[p.prayer]}',
        body: 'It is time for ${p.prayer.displayName}.',
        payload: '/home/prayer',
        scheduledDate: p.at,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'adhan',
            'Adhan reminders',
            channelDescription: 'An alert at each prayer time',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // shortcut: inexact can fire a few minutes late on Android; exact
        // alarms need SCHEDULE_EXACT_ALARM (user-granted on 14+). Upgrade if
        // users report late adhan.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  } catch (e) {
    debugPrint('adhan reminders: scheduling failed: $e');
  }
}
