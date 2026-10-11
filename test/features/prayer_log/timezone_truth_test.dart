// The prayer log must never state something false about either spouse when
// their timezones differ. These tests pin the specific falsehoods the feature
// used to tell:
//
//   1. a partner's completed prayer rendered as "Not yet" (her row was filed
//      under her own date key and dropped by a viewer-anchored filter);
//   2. "Both prayed" being structurally unreachable across zones;
//   3. "together" claimed for check-ins ten hours apart;
//   4. "0 of 5" presented as neglect when her day had barely started.

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/time/local_day.dart';
import 'package:lovinity/core/time/prayer_engine.dart';
import 'package:lovinity/core/time/timezone_bootstrap.dart';
import 'package:lovinity/features/prayer_log/domain/prayer_log_providers.dart';

/// Toronto 3:04 PM Thursday 6 Aug == Dhaka 1:04 AM Friday 7 Aug.
final _instant = DateTime.utc(2026, 8, 6, 19, 4);

PrayerDayView _view({
  String ownTz = 'America/Toronto',
  String? spouseTz = 'Asia/Dhaka',
  int offset = 0,
  String? spouseName = 'Aisha',
}) =>
    PrayerDayView(
      ownTz: ownTz,
      spouseTz: spouseTz,
      ownDay: dayForOffset(tzId: ownTz, offset: offset, at: _instant),
      spouseDay: spouseTz == null
          ? null
          : dayForOffset(tzId: spouseTz, offset: offset, at: _instant),
      now: _instant,
      spouseName: spouseName,
    );

void main() {
  setUpAll(() async => initTimezones());

  group('PrayerDayKeys', () {
    final keys = PrayerDayKeys(
      ownUserId: 'him',
      ownKey: '2026-08-06',
      spouseUserId: 'her',
      spouseKey: '2026-08-07',
    );

    test('maps each spouse to their own day, not to a shared one', () {
      expect(keys.byUserId, {'him': '2026-08-06', 'her': '2026-08-07'});
    });

    test('reports disagreement so the header can expand the dual clock', () {
      expect(keys.agree, isFalse);
      expect(
        const PrayerDayKeys(
          ownUserId: 'him',
          ownKey: '2026-08-06',
          spouseUserId: 'her',
          spouseKey: '2026-08-06',
        ).agree,
        isTrue,
      );
    });

    test('omits the spouse entirely when unpaired', () {
      const solo = PrayerDayKeys(
        ownUserId: 'him',
        ownKey: '2026-08-06',
        spouseUserId: null,
        spouseKey: null,
      );
      expect(solo.byUserId, {'him': '2026-08-06'});
      expect(solo.agree, isTrue);
    });

    // This is load-bearing, not cosmetic: the realtime subscription is keyed
    // on this value and it is recomputed on a 30-second ticker. Without value
    // equality the prayer-log stream would be torn down and re-opened twice a
    // minute, and the notification detector's baseline would reset with it.
    test('is value-equal so a 30s tick does not re-subscribe the stream', () {
      final identical = PrayerDayKeys(
        ownUserId: 'him',
        ownKey: '2026-08-06',
        spouseUserId: 'her',
        spouseKey: '2026-08-07',
      );
      expect(identical, equals(keys));
      expect(identical.hashCode, equals(keys.hashCode));

      final rolledOver = PrayerDayKeys(
        ownUserId: 'him',
        ownKey: '2026-08-07',
        spouseUserId: 'her',
        spouseKey: '2026-08-07',
      );
      expect(rolledOver, isNot(equals(keys)));
    });
  });

  group('PrayerDaySummary', () {
    PrayerDaySummary summary({
      Set<Prayer> own = const {},
      Set<Prayer> spouse = const {},
      Duration? gap,
    }) =>
        PrayerDaySummary(own: own, spouse: spouse, closestGap: gap);

    test('matches on completion, which is reachable across any distance', () {
      final s = summary(
        own: {Prayer.fajr, Prayer.dhuhr, Prayer.asr},
        spouse: {Prayer.dhuhr, Prayer.asr, Prayer.maghrib},
        gap: const Duration(hours: 9, minutes: 41),
      );
      expect(s.matched, {Prayer.dhuhr, Prayer.asr});
      expect(s.matchedCount, 2);
    });

    test('refuses to call a 9h gap shared time', () {
      final s = summary(
        own: {Prayer.asr},
        spouse: {Prayer.asr},
        gap: const Duration(hours: 9, minutes: 41),
      );
      expect(s.matchedCount, 1, reason: 'they did both pray it');
      expect(s.sharedInTime, isFalse, reason: 'but not at the same time');
    });

    test('does call a 6-minute gap shared time', () {
      final s = summary(
        own: {Prayer.asr},
        spouse: {Prayer.asr},
        gap: const Duration(minutes: 6),
      );
      expect(s.sharedInTime, isTrue);
    });

    test('treats the window boundary as inclusive', () {
      expect(
        summary(own: {Prayer.asr}, spouse: {Prayer.asr}, gap: kTogethernessWindow)
            .sharedInTime,
        isTrue,
      );
      expect(
        summary(
          own: {Prayer.asr},
          spouse: {Prayer.asr},
          gap: kTogethernessWindow + const Duration(seconds: 1),
        ).sharedInTime,
        isFalse,
      );
    });

    test('claims nothing when there is no overlap', () {
      final s = summary(own: {Prayer.fajr}, spouse: {Prayer.isha});
      expect(s.matched, isEmpty);
      expect(s.sharedInTime, isFalse);
    });
  });

  group('isPrayerDueForSpouse', () {
    // Built in setUpAll, not at declaration time: group bodies run before any
    // setUpAll, so computing this eagerly would hit the timezone database
    // before initTimezones() has loaded it.
    late final List<ScheduledPrayer> schedule;
    setUpAll(() {
      schedule = prayerTimesForDay(
        date: DateTime(2026, 8, 7),
        loc: const PrayerLocation(
          latitude: 23.8103,
          longitude: 90.4125,
          timezone: 'Asia/Dhaka',
        ),
      );
    });

    test('Fajr is due at 1:04 AM Dhaka only once Fajr has passed', () {
      // At 1:04 AM her Fajr (~4:15 AM) has not arrived. Reporting "Not yet"
      // here would read as though she had skipped it.
      expect(
        isPrayerDueForSpouse(
            prayer: Prayer.fajr, schedule: schedule, now: _instant),
        isFalse,
      );
    });

    test('Isha is not due in the small hours of her own day', () {
      expect(
        isPrayerDueForSpouse(
            prayer: Prayer.isha, schedule: schedule, now: _instant),
        isFalse,
      );
    });

    test('everything is due once her day is well underway', () {
      // 18:00 UTC on the 7th is midnight on the 8th in Dhaka — her whole day
      // has elapsed.
      final endOfHerDay = DateTime.utc(2026, 8, 7, 17, 30);
      for (final p in Prayer.values) {
        expect(
          isPrayerDueForSpouse(prayer: p, schedule: schedule, now: endOfHerDay),
          isTrue,
          reason: '${p.displayName} should be due by the end of her day',
        );
      }
    });

    test('assumes due when no schedule is available', () {
      // She has never set a location. The UI must fall back to making no
      // excuse rather than inventing one.
      expect(
        isPrayerDueForSpouse(
            prayer: Prayer.isha, schedule: null, now: _instant),
        isTrue,
      );
    });
  });

  group('spouseOffsetSentence', () {
    test('names the direction of the gap', () {
      expect(spouseOffsetSentence(_view()), 'Aisha is 10h ahead');
    });

    test('inverts correctly when the spouse is behind', () {
      final v = _view(ownTz: 'Asia/Dhaka', spouseTz: 'America/Toronto');
      expect(spouseOffsetSentence(v), 'Aisha is 10h behind');
    });

    test('is empty when both share an offset', () {
      final v = _view(ownTz: 'America/Toronto', spouseTz: 'America/New_York');
      expect(spouseOffsetSentence(v), '');
    });

    test('falls back to a neutral noun with no display name', () {
      final v = _view(spouseName: null);
      expect(spouseOffsetSentence(v), 'Your spouse is 10h ahead');
    });
  });

  group('spouseDayProgressLabel', () {
    test('explains an early hour rather than leaving 0 of 5 unqualified', () {
      expect(
        spouseDayProgressLabel(view: _view(), offset: 0),
        "Aisha's day has only just begun",
      );
    });

    test('is silent when both are on the same day', () {
      final v = _view(ownTz: 'America/Toronto', spouseTz: 'America/New_York');
      expect(spouseDayProgressLabel(view: v, offset: 0), '');
    });

    test('is silent for past days, where progress is meaningless', () {
      expect(spouseDayProgressLabel(view: _view(offset: 1), offset: 1), '');
    });

    test('is silent when unpaired', () {
      expect(
        spouseDayProgressLabel(view: _view(spouseTz: null), offset: 0),
        '',
      );
    });
  });

  group('PrayerDayView.zonesDiffer', () {
    test('true when the two anchors land on different calendar days', () {
      expect(_view().zonesDiffer, isTrue);
    });

    test('false for two zones that merely share a day', () {
      // Toronto and São Paulo are an hour apart but on the same date here —
      // the header should stay collapsed, since there is nothing to explain.
      final v = _view(spouseTz: 'America/Sao_Paulo');
      expect(v.zonesDiffer, isFalse);
    });

    test('false when unpaired', () {
      expect(_view(spouseTz: null).zonesDiffer, isFalse);
    });
  });
}
