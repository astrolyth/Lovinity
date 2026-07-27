import '../../../shared/models/cycle_record.dart';

int maxHaidDays(String madhhab) => madhhab == 'hanafi' ? 10 : 15;

class CyclePrediction {
  const CyclePrediction({this.nextStart, this.avgCycleLength, this.avgPeriodLength});
  final DateTime? nextStart;
  final int? avgCycleLength;
  final int? avgPeriodLength;
}

/// [history] newest-first. Needs >= 2 records to predict.
CyclePrediction predictCycle(List<CycleRecord> history, {DateTime? today}) {
  if (history.length < 2) return const CyclePrediction();
  // Oldest-first for gap math.
  final ordered = [...history]..sort((a, b) => a.startedOn.compareTo(b.startedOn));

  final cycleGaps = <int>[];
  for (var i = 1; i < ordered.length; i++) {
    cycleGaps.add(ordered[i].startedOn.difference(ordered[i - 1].startedOn).inDays);
  }
  final periodLengths = <int>[];
  for (final rec in ordered) {
    if (rec.endedOn != null) {
      // inclusive day count
      periodLengths.add(rec.endedOn!.difference(rec.startedOn).inDays);
    }
  }

  int? avg(List<int> xs) =>
      xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length).round();

  final avgCycle = avg(cycleGaps);
  final lastStart = ordered.last.startedOn;
  final next = avgCycle == null ? null : lastStart.add(Duration(days: avgCycle));

  return CyclePrediction(
    nextStart: next,
    avgCycleLength: avgCycle,
    avgPeriodLength: avg(periodLengths),
  );
}
