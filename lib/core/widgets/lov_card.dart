import 'package:flutter/material.dart';

import '../theme/tokens.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? LovRadius.lg;

    final bg = switch (variant) {
      LovCardVariant.plain => theme.colorScheme.surface,
      LovCardVariant.tonal => theme.colorScheme.surfaceContainerLow,
      LovCardVariant.outlined => Colors.transparent,
    };

    final border = variant == LovCardVariant.outlined
        ? Border.all(color: theme.colorScheme.outlineVariant)
        : (variant == LovCardVariant.plain
            ? Border.all(
                color: isDark ? LovColors.dividerDark : LovColors.divider,
                width: 0.5,
              )
            : null);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: border,
            boxShadow: variant == LovCardVariant.plain
                ? (isDark ? LovElevation.cardDark : LovElevation.card)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
