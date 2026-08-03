import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/question_repository.dart';
import '../domain/question_providers.dart';

class QuestionScreen extends ConsumerStatefulWidget {
  const QuestionScreen({super.key});

  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final question = ref.read(currentQuestionProvider).value;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (question == null || couple == null || session == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(questionRepositoryProvider).submit(
            coupleId: couple.id,
            userId: session.user.id,
            questionId: question.id,
            answer: text,
          );
      unawaited(LovHaptics.selection());
      _controller.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questionAsync = ref.watch(currentQuestionProvider);
    final session = ref.watch(authSessionProvider).asData?.value;
    final ownName = ref.watch(ownProfileProvider).asData?.value?.displayName;
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName;
    final answersAsync = ref.watch(questionAnswersProvider);
    final answers = answersAsync.asData?.value ?? const <QuestionAnswer>[];

    // On "Next question" the invalidate refreshes seamlessly: the state stays
    // AsyncData carrying the previous question with `isLoading` set, so
    // `asData?.value` would hand back the stale answered question too --
    // the isLoading/hasValue guard below, not the accessor, is what routes
    // that frame to the shimmer. `.value` differs only for an error carrying
    // a previous value, where it keeps the question up rather than claiming
    // the queue is exhausted; past the guard a null `q` means exactly that.
    final q = questionAsync.value;
    final myId = session?.user.id;
    final myAnswer =
        answers.where((a) => a.authorId == myId).cast<QuestionAnswer?>().firstOrNull;
    final spouseAnswer = answers
        .where((a) => a.authorId != myId)
        .cast<QuestionAnswer?>()
        .firstOrNull;
    // Both sides in: the answers reveal, the composer is gone for good, and
    // the queue advances only when the user taps "Next question".
    final bothAnswered = myAnswer != null && spouseAnswer != null;

    final Widget body;
    if (questionAsync.isLoading || !questionAsync.hasValue) {
      // In flight (first load or a "Next question" refetch), or errored
      // without ever resolving -- none of which is an exhausted queue, which
      // resolves to a real `null` value below.
      body = const Center(child: LovShimmerBox(height: 24, width: 240));
    } else if (q == null) {
      body = const _QueueEmptyState();
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: LovSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LovEnter(
              child: Text(
                q.question,
                style: theme.textTheme.displaySmall?.copyWith(
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: LovSpace.xxxl),

            // Your answer
            LovEnter(
              delay: const Duration(milliseconds: 100),
              child: _AnswerBlock(
                label: myAnswer == null ? 'Your answer' : (ownName ?? 'You'),
                answer: myAnswer?.answer,
                isOwn: true,
              ),
            ),

            // Composer -- gone the moment you've answered. An answer is
            // final: there is deliberately no edit affordance afterwards.
            if (myAnswer == null) ...[
              const SizedBox(height: LovSpace.md),
              LovEnter(
                delay: const Duration(milliseconds: 160),
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'A sentence, a paragraph, whatever fits.',
                  ),
                ),
              ),
              const SizedBox(height: LovSpace.md),
              LovEnter(
                delay: const Duration(milliseconds: 220),
                child: LovButton(
                  label: 'Send answer',
                  icon: Icons.send_rounded,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                  expand: true,
                ),
              ),
            ],

            const SizedBox(height: LovSpace.xxl),

            // Spouse's answer (blurred until you've answered)
            LovEnter(
              delay: const Duration(milliseconds: 280),
              child: _AnswerBlock(
                label: spouseName ?? 'Your spouse',
                answer: spouseAnswer?.answer,
                isOwn: false,
                hidden: myAnswer == null && spouseAnswer != null,
                pending: spouseAnswer == null,
              ),
            ),

            // Advancing the queue is an explicit act. Nothing else on this
            // screen may invalidate currentQuestionProvider -- if the second
            // answer landing advanced it automatically, the reveal would be
            // swapped away before either partner could read it.
            if (bothAnswered) ...[
              const SizedBox(height: LovSpace.xxl),
              LovEnter(
                delay: const Duration(milliseconds: 340),
                child: LovButton(
                  label: 'Next question',
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: () => ref.invalidate(currentQuestionProvider),
                  expand: true,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LovScaffold(
      title: 'Question',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: body,
    );
  }
}

/// Shown when the queue is exhausted -- the couple has answered every
/// approved question and the generator hasn't added a new one yet.
class _QueueEmptyState extends StatelessWidget {
  const _QueueEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: LovSpace.lg),
          Text(
            "You're all caught up",
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LovSpace.sm),
          Text(
            'New questions are on their way. Check back soon.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({
    required this.label,
    required this.isOwn,
    this.answer,
    this.hidden = false,
    this.pending = false,
  });

  final String label;
  final String? answer;
  final bool isOwn;
  final bool hidden;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: LovSpace.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(LovSpace.lg),
          decoration: BoxDecoration(
            color: isOwn
                ? theme.colorScheme.secondary
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(LovRadius.lg),
          ),
          child: pending
              ? Text(
                  isOwn
                      ? 'Send your answer to unlock theirs.'
                      : 'Waiting for their answer.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    fontStyle: FontStyle.italic,
                  ),
                )
              : hidden
                  ? Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: LovSpace.xs),
                        Text(
                          'Answer to reveal.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      answer ?? '',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: isOwn
                            ? theme.colorScheme.onSecondary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
        ),
      ],
    );
  }
}
