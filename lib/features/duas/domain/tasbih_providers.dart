import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/tasbih_channel.dart';
import '../data/tasbih_repository.dart';
import 'tap_batcher.dart';

export '../data/tasbih_repository.dart' show DhikrCounter, CounterTotals;

final tasbihRepositoryProvider = Provider<TasbihRepository>(
  (ref) => TasbihRepository(ref.read(supabaseClientProvider)),
);

final tasbihCountersProvider = StreamProvider<List<DhikrCounter>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(tasbihRepositoryProvider).watchCounters(coupleId);
});

final counterTotalsProvider =
    FutureProvider.autoDispose.family<CounterTotals, String>((ref, id) async {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  if (selfId == null) return const CounterTotals(mine: 0, spouse: 0);
  return ref.read(tasbihRepositoryProvider).totals(id, selfId: selfId);
});

/// Owned (disposed) by the session screen, not by the provider.
final tasbihChannelProvider =
    Provider.autoDispose.family<TasbihChannel, String>((ref, counterId) {
  final selfId = ref.read(authSessionProvider).asData!.value!.user.id;
  final coupleId = ref.read(currentCoupleProvider).asData!.value!.id;
  return TasbihChannel(
    supabase: ref.read(supabaseClientProvider),
    coupleId: coupleId,
    selfId: selfId,
    counterId: counterId,
  );
});

/// Outlives the session screen so unsaved taps keep retrying (5 s) after the
/// user leaves, e.g. while offline. Ids are captured at creation.
final tasbihBatcherProvider =
    Provider.family<TapBatcher, String>((ref, counterId) {
  final selfId = ref.read(authSessionProvider).asData!.value!.user.id;
  final coupleId = ref.read(currentCoupleProvider).asData!.value!.id;
  final repo = ref.read(tasbihRepositoryProvider);
  late final TapBatcher batcher;
  batcher = TapBatcher(
    flushEvery: const Duration(seconds: 5),
    save: (n) async {
      await repo.addContribution(
        counterId: counterId,
        coupleId: coupleId,
        userId: selfId,
        count: n,
      );
      // Let the list pick up fresh totals once everything is saved.
      if (batcher.pending == 0) ref.invalidate(counterTotalsProvider(counterId));
    },
  );
  ref.onDispose(batcher.dispose);
  return batcher;
});
