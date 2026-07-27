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
/// current couple changes, not on every rebuild.
final dailyContentProvider = FutureProvider<DailyContent?>((ref) async {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (couple == null) return null;
  return ref.read(dailyContentRepositoryProvider).forDate();
});
