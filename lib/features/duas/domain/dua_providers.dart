import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/dua_repository.dart';

final duaRepositoryProvider = Provider<DuaRepository>((ref) {
  return DuaRepository(ref.read(supabaseClientProvider));
});

/// All couple's duas (respecting RLS on private/shared visibility).
final duasProvider = StreamProvider<List<Dua>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final session = ref.watch(authSessionProvider).asData?.value;
  if (couple == null || session == null) return const Stream.empty();
  final me = session.user.id;
  return ref.read(duaRepositoryProvider).watch(couple.id).map(
        (rows) => rows
            .where((d) => d.visibility == 'shared' || d.authorId == me)
            .toList(growable: false),
      );
});

/// Open duas (not yet answered). Newest first.
final openDuasProvider = Provider<List<Dua>>((ref) {
  final all = ref.watch(duasProvider).asData?.value ?? const [];
  return all.where((d) => !d.isAnswered).toList();
});

/// Answered duas. Newest first.
final answeredDuasProvider = Provider<List<Dua>>((ref) {
  final all = ref.watch(duasProvider).asData?.value ?? const [];
  return all.where((d) => d.isAnswered).toList();
});
