import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../data/scoreboard_repository.dart';
import 'score_engine.dart';

final scoreboardRepositoryProvider = Provider<ScoreboardRepository>((ref) {
  return ScoreboardRepository(ref.read(supabaseClientProvider));
});

class CoupleScoreboard {
  const CoupleScoreboard({required this.own, required this.spouse});
  final ScoreResult own;
  final ScoreResult spouse;
}

/// Window length in days for the headline comparison.
const int scoreWindowDays = 30;

/// Computes both members' scores via the `get_couple_scoreboard` SECURITY
/// DEFINER RPC (see `supabase/migrations/20260715000005_scoreboard_rpc.sql`).
/// The RPC reads each member's own cycle_records server-side (bypassing RLS)
/// so a wife's private cycle exemptions apply correctly to her score without
/// ever exposing her cycle rows to her husband's device.
final scoreboardProvider = FutureProvider<CoupleScoreboard?>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (session == null || couple == null) return null;

  // Recompute when today's logs change, or when own cycle history changes
  // (starting/ending a cycle should immediately re-run the scoreboard).
  ref.watch(prayerLogRefreshTickProvider);
  ref.watch(ownCycleHistoryProvider);

  final client = ref.read(supabaseClientProvider);
  final myId = session.user.id;
  final spouseId = couple.spouseOf(myId);

  // Pass the client's LOCAL today so the window matches the local dates that
  // prayer_logs.date rows are written with (the DB's current_date is UTC).
  final now = DateTime.now();
  final localToday =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  final rows = await client.rpc('get_couple_scoreboard',
      params: {'p_window_days': scoreWindowDays, 'p_today': localToday});

  ScoreResult? own;
  ScoreResult? spouse;
  for (final r in (rows as List)) {
    final m = Map<String, dynamic>.from(r as Map);
    final result = ScoreResult(
      prayed: m['prayed'] as int,
      due: m['due'] as int,
      currentStreak: m['current_streak'] as int,
      longestStreak: m['longest_streak'] as int,
    );
    if (m['member_id'] == myId) {
      own = result;
    } else if (m['member_id'] == spouseId) {
      spouse = result;
    }
  }
  if (own == null || spouse == null) return null;

  return CoupleScoreboard(own: own, spouse: spouse);
});
