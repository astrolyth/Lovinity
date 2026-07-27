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
import '../domain/daily_content_providers.dart';
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
    final content = ref.read(dailyContentProvider).asData?.value;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (content?.question == null || couple == null || session == null) return;

    setState(() => _submitting = true);
    try {
      await ref.read(questionRepositoryProvider).submit(
            coupleId: couple.id,
            userId: session.user.id,
            questionId: content!.question!.id,
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
    final content = ref.watch(dailyContentProvider).asData?.value;
    final session = ref.watch(authSessionProvider).asData?.value;
    final ownName = ref.watch(ownProfileProvider).asData?.value?.displayName;
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName;
    final answersAsync = ref.watch(questionAnswersProvider);
    final answers = answersAsync.asData?.value ?? const <QuestionAnswer>[];

    final q = content?.question;
    final myId = session?.user.id;
    final myAnswer =
        answers.where((a) => a.authorId == myId).cast<QuestionAnswer?>().firstOrNull;
    final spouseAnswer = answers
        .where((a) => a.authorId != myId)
        .cast<QuestionAnswer?>()
        .firstOrNull;

    return LovScaffold(
      title: 'Question',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: q == null
          ? const Center(child: LovShimmerBox(height: 24, width: 240))
          : SingleChildScrollView(
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
                      label: myAnswer == null
                          ? 'Your answer'
                          : (ownName ?? 'You'),
                      answer: myAnswer?.answer,
                      isOwn: true,
                    ),
                  ),

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
                ],
              ),
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
