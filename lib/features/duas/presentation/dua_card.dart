import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/dua_providers.dart';

class DuaCard extends ConsumerWidget {
  const DuaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final open = ref.watch(openDuasProvider);
    final answered = ref.watch(answeredDuasProvider).length;
    final peek = open.take(3).toList();

    return LovCard(
      onTap: () => context.push('/home/duas'),
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pan_tool_alt_outlined,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: LovSpace.xs),
              Text(
                'Our duas',
                style: theme.textTheme.labelMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (answered > 0)
                Text(
                  '$answered answered',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          if (peek.isEmpty)
            Text(
              'No duas yet. Add the first one.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            )
          else
            Column(
              children: [
                for (final d in peek)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LovSpace.sm),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: LovSpace.sm),
                        Expanded(
                          child: Text(
                            d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: LovSpace.sm),
          Row(
            children: [
              Text(
                open.length > 3 ? '${open.length - 3} more' : 'Open list',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
