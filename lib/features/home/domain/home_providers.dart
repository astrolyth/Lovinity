import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/time/prayer_engine.dart';
import '../../../shared/models/user_profile.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';

/// Own profile (from public.users).
final ownProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return null;
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('users')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();
  if (row == null) return null;
  return UserProfile.fromRow(Map<String, dynamic>.from(row));
});

/// True when signed in but the profile has no gender yet (onboarding pending).
final needsOnboardingProvider = Provider<bool>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return false;
  final profile = ref.watch(ownProfileProvider).asData?.value;
  return profile != null && profile.gender == null;
});

/// Spouse profile (the other member of the couple).
final spouseProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (session == null || couple == null) return null;
  final spouseId = couple.spouseOf(session.user.id);
  final row = await ref
      .read(supabaseClientProvider)
      .from('users')
      .select()
      .eq('id', spouseId)
      .maybeSingle();
  if (row == null) return null;
  return UserProfile.fromRow(Map<String, dynamic>.from(row));
});

/// Emits DateTime.now() every 30 seconds. Used to drive countdowns without
/// putting a long-running `while (true)` inside a `ref.watch`ing generator
/// — a pattern that fights with Riverpod's invalidation during builds.
///
/// Public because the prayer log's dual clock needs the same heartbeat to keep
/// both spouses' local times current. Watch it only from things that genuinely
/// re-render every tick: anything that opens a subscription must depend on a
/// value that changes at most daily (see [todayKeyProvider]) instead, or it
/// will tear down and rebuild that subscription every 30 seconds.
final nowTickerProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  ).asBroadcastStream();
});

/// The current local calendar day as a `YYYY-MM-DD` key. Derived from the
/// same 30s ticker as [nextPrayerProvider], but a `Provider`'s default
/// `==`-based notification means watchers only rebuild when this *string*
/// actually changes -- i.e. once at midnight -- not every 30 seconds, even
/// though this provider itself recomputes that often. Lets long-lived
/// listeners (e.g. the prayer notification pump) re-subscribe once a day
/// changes instead of either never rebuilding (stuck on yesterday) or
/// rebuilding on every tick (dropping in-flight state every 30s).
final todayKeyProvider = Provider<String>((ref) {
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
});

/// Pure computed provider — recomputes when profile or ticker changes.
final nextPrayerProvider = Provider<ScheduledPrayer?>((ref) {
  final profile = ref.watch(ownProfileProvider).asData?.value;
  // Watch the ticker so this provider re-emits every 30s.
  ref.watch(nowTickerProvider);
  if (profile == null ||
      profile.latitude == null ||
      profile.longitude == null) {
    return null;
  }
  final loc = PrayerLocation(
    latitude: profile.latitude!,
    longitude: profile.longitude!,
    timezone: profile.timezone,
  );
  final config = PrayerConfig(
    madhab: profile.madhhab == 'hanafi' ? Madhab.hanafi : Madhab.shafi,
    method: calcMethodFromDb(profile.calcMethod),
  );
  return nextPrayer(now: DateTime.now(), loc: loc, config: config);
});

/// Maps a `users.calc_method` value to its enum. Public because the prayer log
/// computes the SPOUSE's prayer times too — to tell "she hasn't prayed Isha"
/// apart from "Isha isn't due where she is yet" — and that needs HER method,
/// not this device's.
CalcMethod calcMethodFromDb(String s) => switch (s) {
      'egyptian' => CalcMethod.egyptian,
      'karachi' => CalcMethod.karachi,
      'umm_al_qura' => CalcMethod.ummAlQura,
      'dubai' => CalcMethod.dubai,
      'moon_sighting_committee' => CalcMethod.moonsightingCommittee,
      'north_america' => CalcMethod.northAmerica,
      'kuwait' => CalcMethod.kuwait,
      'qatar' => CalcMethod.qatar,
      'singapore' => CalcMethod.singapore,
      'turkey' => CalcMethod.turkey,
      'tehran' => CalcMethod.tehran,
      _ => CalcMethod.muslimWorldLeague,
    };

/// Compose "Fajr in 2h 14m" style label for a scheduled prayer.
String nextPrayerLabel(ScheduledPrayer? sp) {
  if (sp == null) return '';
  final now = DateTime.now();
  final diff = sp.at.difference(now);
  if (diff.isNegative) return '${sp.prayer.displayName} now';
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  if (h == 0) return '${sp.prayer.displayName} in ${m}m';
  return '${sp.prayer.displayName} in ${h}h ${m}m';
}

/// Bump to force score recompute after a prayer is logged/unlogged.
final prayerLogRefreshTickProvider = StateProvider<int>((ref) => 0);

/// A friendly greeting adapted to time of day.
String greetingForHour(int hour) {
  if (hour < 5) return 'Peace, night owl';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  if (hour < 21) return 'Good evening';
  return 'Peace of night';
}
