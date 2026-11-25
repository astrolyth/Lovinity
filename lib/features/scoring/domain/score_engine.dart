/// One member's prayer score, as returned by the `get_couple_scoreboard`
/// RPC. The scoring rule itself lives only in that SQL function.
class ScoreResult {
  const ScoreResult({
    required this.prayed,
    required this.due,
    required this.currentStreak,
    required this.longestStreak,
  });
  final int prayed;
  final int due;
  final int currentStreak;
  final int longestStreak;
  double get pct => due == 0 ? 1.0 : prayed / due;
}
