import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class SakScaffold extends StatelessWidget {
  const SakScaffold({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions,
    this.leading,
    this.padded = true,
    this.centerTitle = false,
    this.showAppBar = true,
    this.floatingActionButton,
    this.backgroundColor,
  });

  final Widget child;
  final String? title;
  final Widget? subtitle;
  final List<Widget>? actions;
  final Widget? leading;
  final bool padded;
  final bool centerTitle;
  final bool showAppBar;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsAppBar = showAppBar &&
        (title != null || subtitle != null || actions != null || leading != null);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: needsAppBar
          ? AppBar(
              leading: leading,
              actions: actions,
              titleSpacing: leading == null ? SakSpace.lg : 0,
              centerTitle: centerTitle,
              toolbarHeight: subtitle != null ? 76 : kToolbarHeight,
              title: Column(
                crossAxisAlignment: centerTitle
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (title != null)
                    Text(title!, style: theme.textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: theme.textTheme.bodySmall,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            )
          : null,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Padding(
          padding: padded
              ? const EdgeInsets.symmetric(horizontal: SakSpace.lg)
              : EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }
}
