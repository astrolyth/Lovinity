import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum SakCardVariant { plain, tonal, outlined }

class SakCard extends StatelessWidget {
  const SakCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SakSpace.lg),
    this.onTap,
    this.variant = SakCardVariant.plain,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final SakCardVariant variant;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? SakRadius.lg;

    final bg = switch (variant) {
      SakCardVariant.plain => theme.colorScheme.surface,
      SakCardVariant.tonal => theme.colorScheme.surfaceContainerLow,
      SakCardVariant.outlined => Colors.transparent,
    };

    final border = variant == SakCardVariant.outlined
        ? Border.all(color: theme.colorScheme.outlineVariant)
        : (variant == SakCardVariant.plain
            ? Border.all(
                color: isDark ? SakColors.dividerDark : SakColors.divider,
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
            boxShadow: variant == SakCardVariant.plain
                ? (isDark ? SakElevation.cardDark : SakElevation.card)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
