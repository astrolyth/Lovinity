import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/question_repository.dart';
import 'daily_content_providers.dart';

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepository(ref.read(supabaseClientProvider));
});

/// Live stream of answers for today's question in this couple. Empty when
/// no couple / no question yet.
final questionAnswersProvider =
    StreamProvider<List<QuestionAnswer>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  final content = ref.watch(dailyContentProvider).asData?.value;
  if (couple == null || content?.question == null) {
    return const Stream.empty();
  }
  return ref.read(questionRepositoryProvider).watchAnswers(
        coupleId: couple.id,
        questionId: content!.question!.id,
      );
});
