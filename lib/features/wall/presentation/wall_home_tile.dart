import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/wall_logic.dart';
import '../domain/wall_models.dart';
import '../domain/wall_providers.dart';
import 'wall_item_thumbnail.dart';
import 'wall_visuals.dart';

/// Home-screen entry to Our Wall: the latest item and an unseen dot.
class WallHomeTile extends ConsumerWidget {
  const WallHomeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(wallItemsProvider).asData?.value ?? const <WallItem>[];
    final latest = items.isEmpty ? null : items.first;
    final hasUnseen = ref.watch(unseenWallItemIdsProvider).isNotEmpty;
    final nameFor = ref.watch(wallNameForProvider);

    return LovCard(
      variant: LovCardVariant.tonal,
      onTap: () => context.go('/home/wall'),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: latest == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(LovRadius.md),
                          ),
                          child: Icon(Icons.auto_awesome_rounded,
                              size: 20, color: scheme.primary),
                        )
                      : WallItemThumbnail(
                          item: latest,
                          borderRadius: LovRadius.md,
                          showSourcePill: false,
                          showPlay: false,
                        ),
                ),
                if (hasUnseen) const Positioned(top: -3, right: -3, child: WallUnseenDot()),
              ],
            ),
          ),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Our Wall', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                if (latest == null)
                  Text(
                    'Share your first find together.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${nameFor(latest.addedBy)} · ${latest.displayTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        ' · ${formatWallTime(latest.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurface.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
