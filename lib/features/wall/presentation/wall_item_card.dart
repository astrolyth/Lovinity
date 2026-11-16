import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../domain/wall_logic.dart';
import '../domain/wall_models.dart';
import 'wall_item_thumbnail.dart';
import 'wall_visuals.dart';

/// Story card: big preview (tap → open link), title + domain, the sharer's
/// note as a quote, and a footer with sharer, time, reactions and comments.
/// Tapping anywhere except the preview opens the item.
class WallItemCard extends StatelessWidget {
  const WallItemCard({
    super.key,
    required this.item,
    required this.sharerName,
    required this.reactions,
    required this.commentCount,
    required this.isUnseen,
    required this.onOpen,
    this.onOpenLink,
  });

  final WallItem item;
  final String sharerName;
  final List<ReactionCount> reactions;
  final int commentCount;
  final bool isUnseen;
  final VoidCallback onOpen;
  final VoidCallback? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasLink = item.url != null;
    final hasPreview = hasLink || item.hasMedia;
    final note = item.note?.trim();
    final hasNote = note != null && note.isNotEmpty;

    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LovRadius.lg),
        side: BorderSide(color: scheme.outlineVariant, width: 0.5),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPreview)
              GestureDetector(
                // Media has no outside link: its preview opens the item.
                onTap: item.hasMedia ? onOpen : onOpenLink,
                child: Hero(
                  tag: wallHeroTag(item.id),
                  child: WallItemThumbnail(item: item, height: 168),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasLink) ...[
                    Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.domain != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.domain!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                  if (hasNote) ...[
                    if (hasPreview) const SizedBox(height: 8),
                    WallNoteQuote(
                      text: note,
                      maxLines: hasPreview ? 4 : 6,
                      large: !hasPreview,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // The chip group may take at most 65% of the row and scales
                  // down beyond that, so the sharer text always keeps room and
                  // nothing overflows on narrow screens / big counts.
                  LayoutBuilder(
                    builder: (context, constraints) => Row(
                      children: [
                        if (isUnseen) ...[
                          const WallUnseenDot(),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            '$sharerName · ${formatWallTime(item.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                        if (reactions.isNotEmpty || commentCount > 0)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.65,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final r in reactions.take(3)) ...[
                                    const SizedBox(width: 4),
                                    _Chip(
                                      label: '${r.kind.emoji} ${r.count}',
                                      highlighted: r.mine,
                                    ),
                                  ],
                                  if (commentCount > 0) ...[
                                    const SizedBox(width: 4),
                                    _Chip(
                                      label: '💬 $commentCount',
                                      highlighted: false,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.highlighted});
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: highlighted ? scheme.secondary : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LovRadius.pill),
        border: Border.all(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
          width: 0.8,
        ),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
