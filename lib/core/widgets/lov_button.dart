import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = widget.onPressed != null && !widget.loading;

    final (fg, bg, border) = _colors(scheme);
    final (vPad, hPad, textStyle, iconSize) = _sizeSpec(theme);

    final content = widget.loading
        ? SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: iconSize, color: fg),
                const SizedBox(width: LovSpace.sm),
              ],
              Text(widget.label, style: textStyle.copyWith(color: fg)),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: LovSpace.sm),
                Icon(widget.trailingIcon, size: iconSize, color: fg),
              ],
            ],
          );

    return AnimatedScale(
      scale: _pressed && enabled ? 0.98 : 1.0,
      duration: LovDuration.quick,
      curve: LovCurves.standard,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LovRadius.pill),
            side: border,
          ),
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            borderRadius: BorderRadius.circular(LovRadius.pill),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              child: widget.expand
                  ? SizedBox(
                      width: double.infinity,
                      child: Center(child: content),
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
  }

  (Color fg, Color bg, BorderSide border) _colors(ColorScheme scheme) {
    switch (widget.variant) {
      case LovButtonVariant.filled:
        return (scheme.onPrimary, scheme.primary, BorderSide.none);
      case LovButtonVariant.tonal:
        return (scheme.onSecondary, scheme.secondary, BorderSide.none);
      case LovButtonVariant.outlined:
        return (
          scheme.onSurface,
          Colors.transparent,
          BorderSide(color: scheme.outlineVariant),
        );
      case LovButtonVariant.text:
        return (scheme.primary, Colors.transparent, BorderSide.none);
    }
  }

  (double vPad, double hPad, TextStyle textStyle, double iconSize) _sizeSpec(
    ThemeData theme,
  ) {
    switch (widget.size) {
      case LovButtonSize.small:
        return (
          LovSpace.sm,
          LovSpace.lg,
          theme.textTheme.labelMedium!,
          16.0,
        );
      case LovButtonSize.medium:
        return (
          LovSpace.md + 2,
          LovSpace.xl,
          theme.textTheme.labelLarge!,
          18.0,
        );
      case LovButtonSize.large:
        return (
          LovSpace.lg,
          LovSpace.xxl,
          theme.textTheme.labelLarge!.copyWith(fontSize: 16),
          20.0,
        );
    }
  }
}
