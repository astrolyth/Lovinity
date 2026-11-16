import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/daily_content.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/daily_content_repository.dart';

final dailyContentRepositoryProvider =
    Provider<DailyContentRepository>((ref) {
  return DailyContentRepository(ref.read(supabaseClientProvider));
});

/// Today's verse and hadith for the couple.
///
/// The question is NO LONGER served from here: it moved to a per-couple
/// queue that advances when both partners answer, not when the calendar
/// rolls over -- see `currentQuestionProvider`. `DailyContent.question` is
/// still hydrated for older builds still reading it, but nothing in this
/// app reads it any more; retiring the field is a separate follow-up.
///
/// Reloads only when the couple id changes (narrowed via `.select`), not on
/// every realtime reconnect of `currentCoupleProvider` -- a raw
/// `.asData?.value` watch would rebuild on every reconnect, each producing
/// an intermediate AsyncLoading and a redundant round trip. (It used to
/// matter more than that: the daily-question notification pump once hung off
/// this provider and every such rebuild re-baselined it. The pump no longer
/// depends on this provider, or on any question id, at all.)
final dailyContentProvider = FutureProvider<DailyContent?>((ref) async {
  final coupleId = ref.watch(
    currentCoupleProvider.select((c) => c.asData?.value?.id),
  );
  if (coupleId == null) return null;
  return ref.read(dailyContentRepositoryProvider).forDate();
});
