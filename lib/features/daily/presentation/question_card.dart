import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../domain/daily_content_providers.dart';
import '../domain/question_providers.dart';

class QuestionCard extends ConsumerWidget {
  const QuestionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final content = ref.watch(dailyContentProvider).asData?.value;
    final session = ref.watch(authSessionProvider).asData?.value;
    final ownName = ref.watch(ownProfileProvider).asData?.value?.displayName;
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName;
    final answers = ref.watch(questionAnswersProvider).asData?.value ?? const [];

    final q = content?.question;
    if (q == null) return const SizedBox.shrink();

    final myId = session?.user.id;
    final myAnswered = answers.any((a) => a.authorId == myId);
    final spouseAnswered = answers.any((a) => a.authorId != myId);
    final bothAnswered = myAnswered && spouseAnswered;

    return LovCard(
      onTap: () => context.push('/home/question'),
      padding: const EdgeInsets.all(LovSpace.xl),
      variant: LovCardVariant.tonal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: LovSpace.xs),
              Text(
                'Question of the day',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          Text(
            q.question,
            style: theme.textTheme.titleLarge?.copyWith(
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: LovSpace.lg),
          Row(
            children: [
              _AnswerChip(
                label: ownName ?? 'You',
                answered: myAnswered,
              ),
              const SizedBox(width: LovSpace.sm),
              _AnswerChip(
                label: spouseName ?? 'Spouse',
                answered: spouseAnswered,
              ),
              const Spacer(),
              Text(
                bothAnswered
                    ? 'Tap to compare'
                    : (myAnswered ? 'Awaiting spouse' : 'Tap to answer'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  const _AnswerChip({required this.label, required this.answered});
  final String label;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: LovMotion.standard,
      curve: LovMotion.enter,
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.sm + 2,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: answered
            ? theme.colorScheme.primary
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(LovRadius.pill),
        border: answered
            ? null
            : Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (answered) ...[
            Icon(
              Icons.check_rounded,
              size: 12,
              color: theme.colorScheme.onPrimary,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: answered
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
