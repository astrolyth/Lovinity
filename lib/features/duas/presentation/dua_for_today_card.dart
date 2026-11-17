import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/adhkar_providers.dart';
import '../domain/dua_suggestions.dart';
import '../domain/suggestion_providers.dart';
import 'library_dua_sheet.dart';

class DuaForTodayCard extends ConsumerWidget {
  const DuaForTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(duaSuggestionsProvider);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final mood = ref.watch(todayMoodProvider).asData?.value;
    final ready = ref.watch(adhkarTodayKeyProvider) != null;
    final s = suggestions.first;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return LovCard(
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A dua for you today',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: LovSpace.md),
          InkWell(
            onTap: () => showLibraryDuaSheet(context, s.dua),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.dua.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: LovSpace.xs),
                Text(s.reason,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
                const SizedBox(height: LovSpace.xs),
                Text(s.dua.translation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ],
            ),
          ),
          const SizedBox(height: LovSpace.md),
          Wrap(
            spacing: LovSpace.xs,
            children: [
              for (final m in Mood.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: mood == m,
                  onSelected: ready
                      ? (_) => ref
                          .read(todayMoodProvider.notifier)
                          .set(mood == m ? null : m)
                      : null,
                ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/home/tasbih'),
              child: const Text('Tasbih together'),
            ),
          ),
        ],
      ),
    );
  }
}
