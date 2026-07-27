import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/cycle_record.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../data/cycle_repository.dart';
import 'cycle_prediction.dart';

final cycleRepositoryProvider = Provider<CycleRepository>((ref) {
  return CycleRepository(ref.read(supabaseClientProvider));
});

final isWifeProvider = Provider<bool>((ref) {
  final profile = ref.watch(ownProfileProvider).asData?.value;
  return profile?.gender == 'female';
});

final ownCycleHistoryProvider = StreamProvider<List<CycleRecord>>((ref) {
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return Stream.value(const []);
  return ref.read(cycleRepositoryProvider).watchOwn(userId: session.user.id);
});

final activeCycleProvider = Provider<CycleRecord?>((ref) {
  final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
  final today = DateTime.now();
  for (final r in history) {
    if (r.isActiveOn(today)) return r;
  }
  return null;
});

final cyclePredictionProvider = Provider<CyclePrediction>((ref) {
  final history = ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
  return predictCycle(history);
});
