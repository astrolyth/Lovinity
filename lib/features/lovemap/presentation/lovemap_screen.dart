import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/lovemap_providers.dart';

/// "How well do you know your spouse?"
class LoveMapScreen extends ConsumerWidget {
  const LoveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final quizzesAsync = ref.watch(loveMapQuizzesProvider);
    final rounds = ref.watch(loveMapRoundsProvider);
    final score = ref.watch(loveMapScoreProvider);
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ??
            'your spouse';

    return LovScaffold(
      title: 'Love map',
      subtitle: Text(score.graded == 0
          ? 'How well do you know $spouseName?'
          : '${score.correct} of ${score.graded} right'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: quizzesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load questions',
              style: theme.textTheme.bodyMedium),
        ),
        data: (_) => rounds.isEmpty
            ? const LovEmpty(
                icon: Icons.psychology_outlined,
                title: 'No questions yet',
                description:
                    'Questions are reviewed before they are published.',
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
                children: [
                  for (final round in rounds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LovSpace.md),
                      child: _RoundCard(
                        round: round,
                        spouseName: spouseName,
                      ),
                    ),
                  const SizedBox(height: LovSpace.xxxl),
                ],
              ),
      ),
    );
  }
}

class _RoundCard extends ConsumerStatefulWidget {
  const _RoundCard({required this.round, required this.spouseName});

  final LoveMapRound round;
  final String spouseName;

  @override
  ConsumerState<_RoundCard> createState() => _RoundCardState();
}

class _RoundCardState extends ConsumerState<_RoundCard> {
  final _truth = TextEditingController();
  final _guess = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _truth.dispose();
    _guess.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final round = widget.round;

    if (round.ownTruth != null && _truth.text != round.ownTruth!.answer) {
      _truth.text = round.ownTruth!.answer;
    }
    if (round.myGuess != null && _guess.text != round.myGuess!.guess) {
      _guess.text = round.myGuess!.guess;
    }

    return LovCard(
      variant: LovCardVariant.plain,
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            round.quiz.categoryLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(round.quiz.question, style: theme.textTheme.titleSmall),
          const SizedBox(height: LovSpace.md),

          // Your own answer, for your spouse to guess later.
          Text('Your answer about yourself',
              style: theme.textTheme.labelMedium),
          const SizedBox(height: LovSpace.xs),
          TextField(
            controller: _truth,
            enabled: !round.hasAnsweredAboutSelf && !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'What is true for you?',
              suffixIcon: round.hasAnsweredAboutSelf
                  ? const Icon(Icons.check, size: 18)
                  : IconButton(
                      icon: const Icon(Icons.send, size: 18),
                      onPressed: _busy ? null : _saveTruth,
                    ),
            ),
          ),

          const SizedBox(height: LovSpace.md),
          Text('Your guess about ${widget.spouseName}',
              style: theme.textTheme.labelMedium),
          const SizedBox(height: LovSpace.xs),
          TextField(
            controller: _guess,
            // One-way by design: committing the guess is what unlocks their
            // answer, so it cannot be revised afterwards.
            enabled: !round.hasGuessed && !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'What do you think they said?',
              suffixIcon: round.hasGuessed
                  ? const Icon(Icons.lock_outline, size: 18)
                  : IconButton(
                      icon: const Icon(Icons.send, size: 18),
                      onPressed: _busy ? null : _saveGuess,
                    ),
            ),
          ),

          if (round.waitingOnSpouse) ...[
            const SizedBox(height: LovSpace.md),
            Text(
              '${widget.spouseName} has not answered this one yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],

          if (round.revealed) ...[
            const SizedBox(height: LovSpace.md),
            LovCard(
              variant: LovCardVariant.tonal,
              padding: const EdgeInsets.all(LovSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.spouseName} said',
                      style: theme.textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(round.spouseTruth!.answer,
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (round.needsGrading) ...[
              const SizedBox(height: LovSpace.sm),
              Row(
                children: [
                  Expanded(
                    child: LovButton(
                      label: 'I got it',
                      size: LovButtonSize.small,
                      onPressed: _busy ? null : () => _grade(true),
                    ),
                  ),
                  const SizedBox(width: LovSpace.sm),
                  Expanded(
                    child: LovButton(
                      label: 'I missed it',
                      variant: LovButtonVariant.text,
                      size: LovButtonSize.small,
                      onPressed: _busy ? null : () => _grade(false),
                    ),
                  ),
                ],
              ),
            ] else if (round.myGuess?.isGraded ?? false) ...[
              const SizedBox(height: LovSpace.sm),
              Row(
                children: [
                  Icon(
                    round.myGuess!.isCorrect!
                        ? Icons.check_circle
                        : Icons.cancel_outlined,
                    size: 16,
                    color: round.myGuess!.isCorrect!
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: LovSpace.xs),
                  Text(
                    round.myGuess!.isCorrect! ? 'You knew this' : 'Now you know',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _saveTruth() async {
    final text = _truth.text.trim();
    if (text.isEmpty) return;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(loveMapRepositoryProvider).setTruth(
            coupleId: couple.id,
            quizId: widget.round.quiz.id,
            subjectId: session.user.id,
            answer: text,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveGuess() async {
    final text = _guess.text.trim();
    if (text.isEmpty) return;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;
    final spouseId = couple.spouseOf(session.user.id);
    setState(() => _busy = true);
    try {
      await ref.read(loveMapRepositoryProvider).submitGuess(
            coupleId: couple.id,
            quizId: widget.round.quiz.id,
            guesserId: session.user.id,
            subjectId: spouseId,
            guess: text,
          );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _grade(bool correct) async {
    final guess = widget.round.myGuess;
    if (guess == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(loveMapRepositoryProvider)
          .grade(guessId: guess.id, isCorrect: correct);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
