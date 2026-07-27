class CycleRecord {
  const CycleRecord({
    required this.id,
    required this.userId,
    required this.coupleId,
    required this.startedOn,
    required this.endedOn,
    required this.visibility,
    this.note,
  });

  final String id;
  final String userId;
  final String coupleId;
  final DateTime startedOn;
  final DateTime? endedOn;
  final String visibility; // 'private' | 'shared'
  final String? note;

  bool get isOpen => endedOn == null;

  /// Whether [day] falls within [startedOn]..[endedOn] (inclusive), treating
  /// an open cycle as active from start onward.
  bool isActiveOn(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final s = DateTime(startedOn.year, startedOn.month, startedOn.day);
    if (d.isBefore(s)) return false;
    if (endedOn == null) return true;
    final e = DateTime(endedOn!.year, endedOn!.month, endedOn!.day);
    return !d.isAfter(e);
  }

  static DateTime _date(String s) => DateTime.parse(s);

  factory CycleRecord.fromRow(Map<String, dynamic> row) => CycleRecord(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        coupleId: row['couple_id'] as String,
        startedOn: _date(row['started_on'] as String),
        endedOn: row['ended_on'] == null ? null : _date(row['ended_on'] as String),
        visibility: (row['visibility'] ?? 'private') as String,
        note: row['note'] as String?,
      );
}
