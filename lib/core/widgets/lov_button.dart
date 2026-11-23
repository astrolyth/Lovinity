import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'lov_kit.dart';

enum LovButtonVariant { filled, outlined, text, tonal }

enum LovButtonSize { small, medium, large }

class LovButton extends StatefulWidget {
  const LovButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = LovButtonVariant.filled,
    this.size = LovButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final LovButtonVariant variant;
  final LovButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;

  @override
  State<LovButton> createState() => _LovButtonState();
}

class _LovButtonState extends State<LovButton> {
  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final enabled = widget.onPressed != null && !widget.loading;
    final height = switch (widget.size) {
      LovButtonSize.small => 40.0,
      LovButtonSize.medium => 54.0,
      LovButtonSize.large => 56.0,
    };
    // The redesign's gold call-to-action.
    if (widget.variant == LovButtonVariant.filled) {
      return LovPrimaryButton(
        label: widget.label,
        icon: widget.icon,
        loading: widget.loading,
        expand: widget.expand,
        height: height,
        onPressed: widget.onPressed,
      );
    }
    final fg = switch (widget.variant) {
      LovButtonVariant.text => p.accent,
      _ => p.text,
    };
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else ...[
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: fg),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: widget.size == LovButtonSize.small ? 14 : 16,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          if (widget.trailingIcon != null) ...[
            const SizedBox(width: 8),
            Icon(widget.trailingIcon, size: 18, color: fg),
          ],
        ],
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: LovPressable(
        onTap: enabled ? widget.onPressed : null,
        child: Opacity(
          opacity: enabled || widget.loading ? 1 : .4,
          child: Container(
            height: widget.variant == LovButtonVariant.text ? 44 : height,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: switch (widget.variant) {
                LovButtonVariant.tonal => p.hi.withValues(alpha: .06),
                LovButtonVariant.outlined => p.hi.withValues(alpha: .04),
                _ => Colors.transparent,
              },
              border: widget.variant == LovButtonVariant.outlined
                  ? Border.all(color: p.hi.withValues(alpha: .1))
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
