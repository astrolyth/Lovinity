import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'lov_kit.dart';

enum LovCardVariant { plain, tonal, outlined }

class LovCard extends StatelessWidget {
  const LovCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LovSpace.lg),
    this.onTap,
    this.variant = LovCardVariant.plain,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final LovCardVariant variant;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final radius = borderRadius ?? 24.0;
    if (variant == LovCardVariant.plain) {
      // The redesign's card: gradient fill, lit hairline, soft depth.
      return LovSurface(
        radius: radius,
        padding: padding,
        onTap: onTap,
        child: child,
      );
    }
    final r = BorderRadius.circular(radius);
    return Material(
      color: variant == LovCardVariant.tonal
          ? p.hi.withValues(alpha: .05)
          : Colors.transparent,
      borderRadius: r,
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            border: variant == LovCardVariant.outlined
                ? Border.all(color: p.line)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
