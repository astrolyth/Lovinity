import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../domain/wall_models.dart';
import 'wall_item_thumbnail.dart';

/// Horizontal row of pinned items, shown above the collection filters.
class WallPinnedRow extends StatelessWidget {
  const WallPinnedRow({
    super.key,
    required this.items,
    required this.nameFor,
    required this.onTap,
  });

  final List<WallItem> items;
  final String Function(String userId) nameFor;
  final void Function(WallItem item) onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PINNED',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: LovSpace.sm),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: LovSpace.sm),
            itemBuilder: (context, i) => _PinnedCard(
              item: items[i],
              subtitle:
                  '${items[i].collection?.label ?? items[i].source.label} · ${nameFor(items[i].addedBy)}',
              onTap: () => onTap(items[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _PinnedCard extends StatelessWidget {
  const _PinnedCard({required this.item, required this.subtitle, required this.onTap});

  final WallItem item;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 150,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LovRadius.md + 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                WallItemThumbnail(
                  item: item,
                  showSourcePill: false,
                  showPlay: false,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                      boxShadow: [
                        BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.35), spreadRadius: 3),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
