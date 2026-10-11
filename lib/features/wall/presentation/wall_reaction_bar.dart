import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../domain/wall_models.dart';

/// One-tap reactions: all six, each toggling independently. Mine are
/// highlighted; counts show when > 0. Taps bounce + give a light haptic.
class WallReactionBar extends StatelessWidget {
  const WallReactionBar({super.key, required this.summary, required this.onToggle});

  final List<ReactionCount> summary;
  final ValueChanged<WallReactionKind> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    ReactionCount? find(WallReactionKind k) {
      for (final r in summary) {
        if (r.kind == k) return r;
      }
      return null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(LovRadius.pill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          for (final k in WallReactionKind.values)
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _ReactionButton(
                    key: Key('reaction-${k.key}'),
                    kind: k,
                    count: find(k)?.count ?? 0,
                    mine: find(k)?.mine ?? false,
                    onTap: () => onToggle(k),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatefulWidget {
  const _ReactionButton({
    super.key,
    required this.kind,
    required this.count,
    required this.mine,
    required this.onTap,
  });

  final WallReactionKind kind;
  final int count;
  final bool mine;
  final VoidCallback onTap;

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> {
  bool _bump = false;

  void _tap() {
    HapticFeedback.lightImpact();
    setState(() => _bump = true);
    Future<void>.delayed(LovMotion.quick, () {
      if (mounted) setState(() => _bump = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: widget.mine,
      label: '${widget.kind.name} reaction',
      child: InkWell(
        onTap: _tap,
        borderRadius: BorderRadius.circular(LovRadius.md),
        child: AnimatedContainer(
          duration: LovMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: widget.mine ? scheme.secondary : Colors.transparent,
            borderRadius: BorderRadius.circular(LovRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _bump ? 1.3 : 1,
                duration: LovMotion.quick,
                curve: LovMotion.springOut,
                child: Text(widget.kind.emoji, style: const TextStyle(fontSize: 20)),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 4),
                Text('${widget.count}', style: theme.textTheme.labelMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
