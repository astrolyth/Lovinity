import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/scoreboard_providers.dart';

class ScoreboardCard extends ConsumerWidget {
  const ScoreboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(scoreboardProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const SizedBox(
              height: 72, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('Could not load scores: $e'),
          data: (board) {
            if (board == null) return const SizedBox.shrink();
            String pct(int prayed, int due) =>
                '${(due == 0 ? 100 : (prayed / due * 100)).round()}%';
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This month', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _Stat(label: 'You',
                    value: pct(board.own.prayed, board.own.due),
                    streak: board.own.currentStreak),
                _Stat(label: 'Spouse',
                    value: pct(board.spouse.prayed, board.spouse.due),
                    streak: board.spouse.currentStreak),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.streak});
  final String label; final String value; final int streak;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Text(value, style: t.headlineMedium),
      Text(label, style: t.bodySmall),
      const SizedBox(height: 4),
      Text('🔥 $streak', style: t.bodySmall),
    ]);
  }
}
