import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum SakButtonVariant { filled, outlined, text, tonal }
enum SakButtonSize { small, medium, large }

class SakButton extends StatefulWidget {
  const SakButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SakButtonVariant.filled,
    this.size = SakButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final SakButtonVariant variant;
  final SakButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;

  @override
  State<SakButton> createState() => _SakButtonState();
}

class _SakButtonState extends State<SakButton> {
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
                const SizedBox(width: SakSpace.sm),
              ],
              Text(widget.label, style: textStyle.copyWith(color: fg)),
              if (widget.trailingIcon != null) ...[
                const SizedBox(width: SakSpace.sm),
                Icon(widget.trailingIcon, size: iconSize, color: fg),
              ],
            ],
          );

    return AnimatedScale(
      scale: _pressed && enabled ? 0.98 : 1.0,
      duration: SakDuration.quick,
      curve: SakCurves.standard,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SakRadius.pill),
            side: border,
          ),
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            borderRadius: BorderRadius.circular(SakRadius.pill),
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
      case SakButtonVariant.filled:
        return (scheme.onPrimary, scheme.primary, BorderSide.none);
      case SakButtonVariant.tonal:
        return (scheme.onSecondary, scheme.secondary, BorderSide.none);
      case SakButtonVariant.outlined:
        return (
          scheme.onSurface,
          Colors.transparent,
          BorderSide(color: scheme.outlineVariant),
        );
      case SakButtonVariant.text:
        return (scheme.primary, Colors.transparent, BorderSide.none);
    }
  }

  (double vPad, double hPad, TextStyle textStyle, double iconSize) _sizeSpec(
    ThemeData theme,
  ) {
    switch (widget.size) {
      case SakButtonSize.small:
        return (
          SakSpace.sm,
          SakSpace.lg,
          theme.textTheme.labelMedium!,
          16.0,
        );
      case SakButtonSize.medium:
        return (
          SakSpace.md + 2,
          SakSpace.xl,
          theme.textTheme.labelLarge!,
          18.0,
        );
      case SakButtonSize.large:
        return (
          SakSpace.lg,
          SakSpace.xxl,
          theme.textTheme.labelLarge!.copyWith(fontSize: 16),
          20.0,
        );
    }
  }
}
