import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/lesson_repository.dart';
import '../domain/learning_providers.dart';

/// The lesson library.
class LessonListScreen extends ConsumerWidget {
  const LessonListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lessonsAsync = ref.watch(lessonsProvider);
    final done = ref.watch(completedLessonCountProvider);

    return LovScaffold(
      title: 'Study together',
      subtitle: Text(done == 0 ? 'Short lessons, then compare' : '$done done'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: lessonsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child:
              Text('Could not load lessons', style: theme.textTheme.bodyMedium),
        ),
        data: (lessons) => lessons.isEmpty
            ? const LovEmpty(
                icon: Icons.menu_book_outlined,
                title: 'No lessons available yet',
                // Honest about the cause. The library is seeded but unapproved,
                // and "nothing here" would wrongly suggest the feature is
                // broken or that content was never written.
                description:
                    'Lessons are reviewed before they are published. They will '
                    'appear here once that review is done.',
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
                children: [
                  for (final lesson in lessons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LovSpace.md),
                      child: _LessonTile(lesson: lesson),
                    ),
                  const SizedBox(height: LovSpace.xxxl),
                ],
              ),
      ),
    );
  }
}

class _LessonTile extends ConsumerWidget {
  const _LessonTile({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(lessonStateProvider(lesson.id));

    return LovCard(
      variant: LovCardVariant.plain,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LessonScreen(lesson: lesson),
        ),
      ),
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.categoryLabel.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(lesson.title, style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          if (state.revealed)
            Icon(Icons.check_circle,
                size: 20, color: theme.colorScheme.primary)
          else if (state.waitingForSpouse)
            Icon(Icons.hourglass_empty,
                size: 20, color: theme.colorScheme.secondary),
        ],
      ),
    );
  }
}

/// One lesson: read it, answer two questions, then compare.
class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  late final List<TextEditingController> _controllers;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (var i = 0; i < widget.lesson.questions.length;
          i++)
        TextEditingController(),
    ];
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = widget.lesson;
    final state = ref.watch(lessonStateProvider(lesson.id));
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ??
            'Your spouse';

    // Once submitted the answers are fixed — a check-in you can edit after
    // seeing your spouse's reply is not a check-in.
    if (state.ownDone) {
      for (var i = 0; i < _controllers.length; i++) {
        final saved = state.own?.answerFor(i);
        if (saved != null && _controllers[i].text != saved) {
          _controllers[i].text = saved;
        }
      }
    }

    return LovScaffold(
      title: lesson.categoryLabel,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
        children: [
          Text(lesson.title, style: theme.textTheme.headlineSmall),
          if (lesson.arabicBody != null) ...[
            const SizedBox(height: LovSpace.lg),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                lesson.arabicBody!,
                style: LovTypography.arabicText(fontSize: 22),
              ),
            ),
          ],
          const SizedBox(height: LovSpace.lg),
          Text(lesson.body, style: theme.textTheme.bodyLarge),
          if (lesson.reference != null) ...[
            const SizedBox(height: LovSpace.md),
            Text(
              lesson.reference!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          if (lesson.hasCheckIn) ...[
            const LovSectionHeader(
              title: 'Check in',
              subtitle: 'You each answer, then you compare',
            ),
            for (var i = 0; i < lesson.questions.length; i++)
              _QuestionBlock(
                question: lesson.questions[i],
                controller: _controllers[i],
                locked: state.ownDone,
                spouseAnswer: state.revealed ? state.spouse?.answerFor(i) : null,
                spouseName: spouseName,
              ),
            const SizedBox(height: LovSpace.lg),
            if (!state.ownDone)
              LovButton(
                label: 'Submit my answers',
                loading: _saving,
                expand: true,
                onPressed: _submit,
              )
            else if (state.waitingForSpouse)
              LovCard(
                variant: LovCardVariant.tonal,
                padding: const EdgeInsets.all(LovSpace.lg),
                child: Text(
                  'Your answers are saved. $spouseName\'s will appear here '
                  'once they have answered too.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
          const SizedBox(height: LovSpace.xxxl),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;

    final answers = <String, String>{
      for (var i = 0; i < _controllers.length; i++)
        '$i': _controllers[i].text.trim(),
    };
    if (answers.values.any((v) => v.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Answer both questions first')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(lessonRepositoryProvider).submit(
            coupleId: couple.id,
            userId: session.user.id,
            lessonId: widget.lesson.id,
            answers: answers,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your answers')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _QuestionBlock extends StatelessWidget {
  const _QuestionBlock({
    required this.question,
    required this.controller,
    required this.locked,
    required this.spouseAnswer,
    required this.spouseName,
  });

  final String question;
  final TextEditingController controller;
  final bool locked;
  final String? spouseAnswer;
  final String spouseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LovSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: theme.textTheme.titleSmall),
          const SizedBox(height: LovSpace.sm),
          TextField(
            controller: controller,
            enabled: !locked,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Your answer'),
          ),
          if (spouseAnswer != null) ...[
            const SizedBox(height: LovSpace.sm),
            LovCard(
              variant: LovCardVariant.tonal,
              padding: const EdgeInsets.all(LovSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spouseName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(spouseAnswer!, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
