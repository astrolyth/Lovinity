import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../domain/wall_logic.dart';
import '../domain/wall_models.dart';
import 'wall_item_thumbnail.dart';
import 'wall_visuals.dart';

/// The latest comment shown under a post.
class WallCommentPreview {
  const WallCommentPreview({required this.author, required this.body});
  final String author;
  final String body;
}

/// A post on Our wall: who shared it, their note, the preview, reactions and
/// a comment preview. Tap React for a heart, hold it for the emoji dock;
/// double-tap the preview to heart it. Presentational — the screen wires the
/// callbacks to the repository.
class WallItemCard extends StatefulWidget {
  const WallItemCard({
    super.key,
    required this.item,
    required this.sharerName,
    required this.reactions,
    required this.commentCount,
    required this.isUnseen,
    required this.onOpen,
    this.onOpenLink,
    this.isMine = false,
    this.avatarName,
    this.lastComment,
    this.onReact,
    this.onTogglePin,
    this.onSave,
  });

  final WallItem item;
  final String sharerName;
  final List<ReactionCount> reactions;
  final int commentCount;
  final bool isUnseen;
  final VoidCallback onOpen;
  final VoidCallback? onOpenLink;
  final bool isMine;

  /// Name for the avatar initial (the card may label your own posts "You").
  final String? avatarName;
  final WallCommentPreview? lastComment;
  final ValueChanged<WallReactionKind>? onReact;
  final VoidCallback? onTogglePin;
  final VoidCallback? onSave;

  @override
  State<WallItemCard> createState() => _WallItemCardState();
}

class _WallItemCardState extends State<WallItemCard> {
  bool _picker = false;
  int _burst = 0;

  ReactionCount? get _mine => widget.reactions.where((r) => r.mine).firstOrNull;

  void _react(WallReactionKind k) {
    setState(() => _picker = false);
    if (k == WallReactionKind.heart && _mine?.kind != k) {
      setState(() => _burst++);
    }
    widget.onReact?.call(k);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final item = widget.item;
    final note = item.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    final hasPreview = item.url != null || item.hasMedia;
    final mine = _mine;
    final others = widget.reactions.where((r) => r.count > (r.mine ? 1 : 0));
    final reactedBy = [
      if (others.isNotEmpty) widget.isMine ? 'They' : widget.sharerName,
      if (mine != null) 'You',
    ];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.cardA, p.cardB],
              ),
              border: Border.all(color: p.hi.withValues(alpha: .07)),
              boxShadow: [
                BoxShadow(
                  color: p.shadow.withValues(alpha: p.isDark ? .9 : .2),
                  blurRadius: 40,
                  spreadRadius: -24,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (item.isPinned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Icon(Icons.push_pin_rounded, size: 13, color: p.accent),
                        const SizedBox(width: 5),
                        LovEyebrow('Pinned', color: p.accent),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    LovAvatar(
                      initial: widget.avatarName ?? widget.sharerName,
                      size: 36,
                      partner: !widget.isMine,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.sharerName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                          Text(
                            'shared from ${item.source.label} · '
                            '${formatWallTime(item.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isUnseen)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: WallUnseenDot(),
                      ),
                    _PinButton(on: item.isPinned, onTap: widget.onTogglePin),
                  ],
                ),
                if (hasNote)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                    child: Text(
                      note,
                      style: const TextStyle(fontSize: 15, height: 1.45),
                    ),
                  ),
                if (hasPreview)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _Media(
                      item: item,
                      burst: _burst,
                      onTap: item.hasMedia ? widget.onOpen : widget.onOpenLink,
                      onDoubleTap: () {
                        if (mine?.kind != WallReactionKind.heart) {
                          _react(WallReactionKind.heart);
                        }
                      },
                    ),
                  ),
                if (widget.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                    child: Wrap(
                      spacing: 0,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final r in widget.reactions) ...[
                          Container(
                            height: 24,
                            constraints: const BoxConstraints(minWidth: 24),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.surface2,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              r.count > 1
                                  ? '${r.kind.emoji} ${r.count}'
                                  : r.kind.emoji,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (reactedBy.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Text(
                              '${reactedBy.join(' and ')} reacted',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: p.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Act(
                      label: mine == null
                          ? 'React. Hold for more'
                          : 'Your reaction: ${mine.kind.emoji}. Hold for more',
                      color: mine == null ? p.text2 : p.partner,
                      onTap: widget.onReact == null
                          ? null
                          : () => _react(mine?.kind ?? WallReactionKind.heart),
                      onLongPress: widget.onReact == null
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              setState(() => _picker = true);
                            },
                      leading: mine == null
                          ? const Icon(Icons.favorite_border_rounded, size: 18)
                          : Text(
                              mine.kind.emoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                      text: 'React',
                    ),
                    _Act(
                      label: 'Comments, ${widget.commentCount}',
                      color: p.text2,
                      onTap: widget.onOpen,
                      leading: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      text: '${widget.commentCount}',
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _Act(
                          label: item.collection == null
                              ? 'Save to an album'
                              : 'Saved to ${item.collection!.label}. Change album',
                          color: item.collection == null ? p.text2 : p.accent,
                          onTap: widget.onSave,
                          leading: Icon(
                            item.collection == null
                                ? Icons.bookmark_border_rounded
                                : Icons.bookmark_rounded,
                            size: 18,
                          ),
                          text: item.collection?.label ?? 'Save',
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.lastComment case final c?)
                  GestureDetector(
                    onTap: widget.onOpen,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${c.author} ',
                                  style: TextStyle(
                                    color: p.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(text: c.body),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: p.text2,
                            ),
                          ),
                          if (widget.commentCount > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'View all ${widget.commentCount} comments',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: p.faint,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_picker) ...[
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _picker = false),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 52,
            child: _Picker(current: mine?.kind, onPick: _react),
          ),
        ],
      ],
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({required this.on, required this.onTap});
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Pin to top',
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? p.accent.withValues(alpha: .12) : Colors.transparent,
          ),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(on),
            tween: Tween(begin: on ? 0 : 1, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: lovBounce,
            builder: (_, v, child) => Transform.rotate(
              angle: -(1 - v) * .7,
              child: Transform.scale(scale: .4 + .6 * v, child: child),
            ),
            child: Icon(
              on ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 18,
              color: on ? p.accent : p.faint,
            ),
          ),
        ),
      ),
    );
  }
}

class _Media extends StatelessWidget {
  const _Media({
    required this.item,
    required this.burst,
    required this.onTap,
    required this.onDoubleTap,
  });
  final WallItem item;
  final int burst;
  final VoidCallback? onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final title = item.url == null ? null : item.displayTitle;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.hi.withValues(alpha: .06)),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Hero(
                  tag: wallHeroTag(item.id),
                  child: WallItemThumbnail(
                    item: item,
                    height:
                        item.source == WallSource.instagram ||
                            item.source == WallSource.tiktok
                        ? 250
                        : 190,
                  ),
                ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        if (item.domain != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              item.domain!,
                              style: TextStyle(fontSize: 12, color: p.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            if (burst > 0)
              Positioned.fill(
                child: IgnorePointer(child: _HeartBurst(key: ValueKey(burst))),
              ),
          ],
        ),
      ),
    );
  }
}

/// The big heart that pops and floats away on a double-tap.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.lov.partner;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1000),
      builder: (_, t, child) {
        final scale = t < .22
            ? .2 + (1.12 - .2) * lovBounce.transform(t / .22)
            : 1.0 + .1 * ((t - .22) / .78);
        final opacity = t < .22
            ? t / .22
            : t < .6
            ? 1.0
            : 1 - (t - .6) / .4;
        final dy = t < .6 ? 0.0 : -50 * (t - .6) / .4;
        return Align(
          alignment: const Alignment(0, -.2),
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(scale: scale, child: child),
            ),
          ),
        );
      },
      child: Icon(
        Icons.favorite_rounded,
        size: 96,
        color: c,
        shadows: [Shadow(color: c.withValues(alpha: .75), blurRadius: 26)],
      ),
    );
  }
}

class _Act extends StatelessWidget {
  const _Act({
    required this.label,
    required this.color,
    required this.leading,
    required this.text,
    this.onTap,
    this.onLongPress,
  });
  final String label;
  final Color color;
  final Widget leading;
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: LovPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: IconTheme(
          data: IconThemeData(color: color),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Reaction dock that pops up from the React button.
class _Picker extends StatelessWidget {
  const _Picker({required this.current, required this.onPick});
  final WallReactionKind? current;
  final ValueChanged<WallReactionKind> onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: lovBounce,
      builder: (_, v, child) => Transform.scale(
        scale: .6 + .4 * v,
        alignment: Alignment.bottomLeft,
        child: Opacity(opacity: v.clamp(0, 1), child: child),
      ),
      child: LovGlass(
        borderRadius: BorderRadius.circular(999),
        blur: 20,
        color: p.surface.withValues(alpha: .92),
        border: Border.all(color: p.hi.withValues(alpha: .1)),
        shadows: [
          BoxShadow(
            color: p.shadow.withValues(alpha: .9),
            blurRadius: 40,
            spreadRadius: -12,
            offset: const Offset(0, 20),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final k in WallReactionKind.values)
                Semantics(
                  button: true,
                  selected: current == k,
                  label: k.name,
                  child: GestureDetector(
                    key: Key('reaction-${k.key}'),
                    onTap: () => onPick(k),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: current == k
                            ? p.accent.withValues(alpha: .18)
                            : Colors.transparent,
                      ),
                      child: Text(
                        k.emoji,
                        style: const TextStyle(fontSize: 25),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
