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
final _nowTickerProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
    const Duration(seconds: 30),
    (_) => DateTime.now(),
  ).asBroadcastStream();
});

/// Pure computed provider — recomputes when profile or ticker changes.
final nextPrayerProvider = Provider<ScheduledPrayer?>((ref) {
  final profile = ref.watch(ownProfileProvider).asData?.value;
  // Watch the ticker so this provider re-emits every 30s.
  ref.watch(_nowTickerProvider);
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
    method: _mapMethod(profile.calcMethod),
  );
  return nextPrayer(now: DateTime.now(), loc: loc, config: config);
});

CalcMethod _mapMethod(String s) => switch (s) {
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
