import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/gratitude_providers.dart';

class GratitudeCard extends ConsumerWidget {
  const GratitudeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wroteToday = ref.watch(wroteGratitudeTodayProvider);
    final notes = ref.watch(gratitudeNotesProvider).asData?.value ?? const [];
    final jarCount = notes.length;

    return LovCard(
      onTap: () => context.push('/home/gratitude'),
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              borderRadius: BorderRadius.circular(LovRadius.md),
            ),
            child: Icon(
              Icons.favorite_outline_rounded,
              size: 20,
              color: theme.colorScheme.onSecondary,
            ),
          ),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wroteToday
                      ? 'You wrote for your spouse today'
                      : 'One thing you love about them',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  jarCount == 0
                      ? 'Fill the jar together.'
                      : '$jarCount ${jarCount == 1 ? 'note' : 'notes'} in the jar.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}
