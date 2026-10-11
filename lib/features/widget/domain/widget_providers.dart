import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../../../core/time/local_day.dart';
import '../../../core/time/tz_sync.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../prayer_log/domain/prayer_log_providers.dart';
import '../data/widget_snapshot.dart';

/// Shared container the app and the native widget both read.
///
/// iOS requires an App Group (both the app target and the widget extension must
/// declare it); Android uses the default SharedPreferences file the
/// `home_widget` plugin manages. Changing either string means the widget
/// silently reads nothing, so they are named once here.
const kWidgetAppGroupId = 'group.com.lovinity.lovinity';
const kWidgetDataKey = 'lovinity_snapshot';
const kIosWidgetName = 'LovinityWidget';
const kAndroidWidgetProvider = 'LovinityWidgetProvider';

/// Writes snapshots into the shared container and asks the OS to redraw.
///
/// Abstracted so the publish logic can be tested without a platform channel.
abstract class WidgetBridge {
  Future<void> publish(WidgetSnapshot snapshot);
}

class HomeWidgetBridge implements WidgetBridge {
  const HomeWidgetBridge();

  @override
  Future<void> publish(WidgetSnapshot snapshot) async {
    await HomeWidget.setAppGroupId(kWidgetAppGroupId);
    await HomeWidget.saveWidgetData<String>(kWidgetDataKey, snapshot.toJson());
    await HomeWidget.updateWidget(
      iOSName: kIosWidgetName,
      androidName: kAndroidWidgetProvider,
    );
  }
}

/// Records the last published snapshot so an unchanged one is not republished.
///
/// Its own provider so it survives rebuilds of the publisher below, which
/// re-runs whenever any of its many dependencies changes.
class _PublishGuard {
  WidgetSnapshot? last;
}

final _publishGuardProvider = Provider<_PublishGuard>((ref) => _PublishGuard());

final widgetBridgeProvider =
    Provider<WidgetBridge>((ref) => const HomeWidgetBridge());

/// Decides whether a snapshot is worth pushing to the OS.
///
/// Pure, so the throttling rule is testable. Republishing on every tick would
/// wake the widget extension constantly for no visible change — on iOS that
/// spends the widget's refresh budget, which is finite and shared, and can get
/// later genuine updates dropped.
bool shouldPublish({
  required WidgetSnapshot next,
  required WidgetSnapshot? last,
}) =>
    !next.sameContentAs(last);

/// Keeps the OS home-screen widget in step with the app.
///
/// Watched once from HomeScreen, alongside the notification pumps.
///
/// The counts come from `prayerDaySummaryProvider`, which resolves each spouse
/// against their OWN day (`lib/core/time/local_day.dart`). That matters more
/// here than anywhere else in the app: a widget has no day toggle and no dual
/// clock of its own, so a count anchored to the wrong day would be a bare,
/// unqualified, wrong number on a lock screen. Both zones travel with it so the
/// native side can attribute each count to a day.
final widgetPublisherProvider = Provider<void>((ref) {
  final summary = ref.watch(prayerDaySummaryProvider);
  final ownProfile = ref.watch(ownProfileProvider).asData?.value;
  final spouseProfile = ref.watch(spouseProfileProvider).asData?.value;
  final deviceTz = ref.watch(deviceTimezoneProvider).asData?.value;
  final nextPrayer = ref.watch(nextPrayerProvider);
  final session = ref.watch(authSessionProvider).asData?.value;

  // Nothing truthful to show before the user is signed in and anchored.
  if (session == null || deviceTz == null) return;

  final snapshot = buildSnapshot(
    ownName: ownProfile?.displayName ?? 'You',
    spouseName: spouseProfile?.displayName ?? 'Your spouse',
    ownCount: summary.ownCount,
    spouseCount: summary.spouseCount,
    ownTz: deviceTz,
    // Falls back to this device's zone rather than UTC when unpaired: equal
    // zones make the widget drop its day-attribution line, which is the right
    // rendering when there is no second person to attribute anything to.
    spouseTz: spouseProfile?.timezone ?? deviceTz,
    now: DateTime.now(),
    nextPrayer: nextPrayer,
    latitude: ownProfile?.latitude,
    longitude: ownProfile?.longitude,
    calcMethod: ownProfile?.calcMethod,
    madhab: ownProfile?.madhhab,
  );

  final guard = ref.read(_publishGuardProvider);
  if (!shouldPublish(next: snapshot, last: guard.last)) return;
  guard.last = snapshot;

  unawaited(() async {
    try {
      await ref.read(widgetBridgeProvider).publish(snapshot);
    } catch (_) {
      // Best effort. A widget that cannot be updated is a degraded surface, not
      // a reason to disturb the app; clearing the guard lets the next change
      // retry rather than being suppressed as a duplicate.
      guard.last = null;
    }
  }());
});

/// The day key each side's count belongs to, for the widget's attribution line.
///
/// Exposed for tests and for any future in-app preview of the widget.
({String ownDay, String spouseDay}) widgetDayKeys({
  required WidgetSnapshot snapshot,
  required DateTime now,
}) =>
    (
      ownDay: dayKey(localDayAt(snapshot.ownTz, now)),
      spouseDay: dayKey(localDayAt(snapshot.spouseTz, now)),
    );
