import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../gratitude/presentation/gratitude_card.dart';
import '../../learning/domain/learning_providers.dart';
import 'question_card.dart';
import 'verse_card.dart';

/// "Today": the verse, the question for you both, gratitude and the next
/// lesson in one calm scroll. Each card opens its full screen.
class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(Widget c, int i) => SliverToBoxAdapter(
      child: LovRise(
        delay: Duration(milliseconds: 100 * i),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, i == 0 ? 8 : 12, 16, 0),
          child: c,
        ),
      ),
    );
    return LovPage(
      title: 'Today',
      slivers: [
        card(const VerseCard(), 0),
        card(const QuestionCard(), 1),
        card(const GratitudeCard(), 2),
        card(const _LessonCard(), 3),
      ],
    );
  }
}

class _LessonCard extends ConsumerWidget {
  const _LessonCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final lessons = ref.watch(lessonsProvider).asData?.value ?? const [];
    final done = ref.watch(completedLessonCountProvider);
    final total = lessons.length;
    final next = total == 0 ? null : lessons[done.clamp(0, total - 1)];
    return LovSurface(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      onTap: () => context.push('/home/learn'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.school_outlined, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 0
                      ? 'Short lessons for two'
                      : 'Lesson ${(done + 1).clamp(1, total)} of $total',
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  next?.title ?? 'Learn together',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 4,
                    color: p.accent,
                    backgroundColor: p.line,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: p.faint),
        ],
      ),
    );
  }
}
