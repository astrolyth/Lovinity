import '../../core/time/prayer_engine.dart';

enum PrayerStatus { prayed, missed, skipped }

extension PrayerStatusX on PrayerStatus {
  String get dbValue => switch (this) {
        PrayerStatus.prayed => 'prayed',
        PrayerStatus.missed => 'missed',
        PrayerStatus.skipped => 'skipped',
      };

  static PrayerStatus fromDb(String value) => switch (value) {
        'missed' => PrayerStatus.missed,
        'skipped' => PrayerStatus.skipped,
        _ => PrayerStatus.prayed,
      };
}

class PrayerLogEntry {
  const PrayerLogEntry({
    required this.userId,
    required this.date,
    required this.prayer,
    required this.status,
    required this.timeLogged,
  });

  final String userId;
  final DateTime date;
  final Prayer prayer;
  final PrayerStatus status;
  final DateTime timeLogged;

  factory PrayerLogEntry.fromRow(Map<String, dynamic> row) {
    return PrayerLogEntry(
      userId: row['user_id'] as String,
      date: DateTime.parse(row['date'] as String),
      prayer: _prayerFromString(row['prayer'] as String),
      status: PrayerStatusX.fromDb(row['status'] as String),
      timeLogged: DateTime.parse(row['time_logged'] as String),
    );
  }
}

Prayer _prayerFromString(String s) => switch (s) {
      'fajr' => Prayer.fajr,
      'dhuhr' => Prayer.dhuhr,
      'asr' => Prayer.asr,
      'maghrib' => Prayer.maghrib,
      'isha' => Prayer.isha,
      _ => Prayer.fajr,
    };

extension PrayerDbName on Prayer {
  String get dbName => switch (this) {
        Prayer.fajr => 'fajr',
        Prayer.dhuhr => 'dhuhr',
        Prayer.asr => 'asr',
        Prayer.maghrib => 'maghrib',
        Prayer.isha => 'isha',
      };
}
