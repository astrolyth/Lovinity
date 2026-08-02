import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/daily_content.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/daily_content_repository.dart';

final dailyContentRepositoryProvider =
    Provider<DailyContentRepository>((ref) {
  return DailyContentRepository(ref.read(supabaseClientProvider));
});

/// Today's verse/hadith/question for the couple. Reloads only when the
/// couple id changes (narrowed via `.select`), not on every realtime
/// reconnect of `currentCoupleProvider` -- a raw `.asData?.value` watch
/// would rebuild on every reconnect (each producing an intermediate
/// AsyncLoading), which re-baselines the daily-question notification pump
/// downstream and swallows partner activity that happened while backgrounded.
final dailyContentProvider = FutureProvider<DailyContent?>((ref) async {
  final coupleId = ref.watch(
    currentCoupleProvider.select((c) => c.asData?.value?.id),
  );
  if (coupleId == null) return null;
  return ref.read(dailyContentRepositoryProvider).forDate();
});
