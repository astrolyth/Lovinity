import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../data/preferences_repository.dart';
import '../data/profile_repository.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>((ref) {
  return PreferencesRepository(ref.read(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.read(supabaseClientProvider));
});

final preferencesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return <String, dynamic>{};
  return ref.read(preferencesRepositoryProvider).fetch(session.user.id);
});

final shareCycleByDefaultProvider = Provider<bool>((ref) {
  final prefs = ref.watch(preferencesProvider).asData?.value ?? const {};
  return prefs['share_cycle_default'] == true;
});
