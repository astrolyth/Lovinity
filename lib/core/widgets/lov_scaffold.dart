import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'lov_kit.dart';

class LovScaffold extends StatelessWidget {
  const LovScaffold({
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
    final p = context.lov;
    final needsAppBar =
        showAppBar &&
        (title != null ||
            subtitle != null ||
            actions != null ||
            leading != null);
    final top = MediaQuery.paddingOf(context).top;

    // Redesign header: glass round buttons either side of a centred display
    // title (a sole leading/action is balanced so the title stays centred).
    Widget glass(Widget w) => LovGlass(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconTheme.merge(
          data: IconThemeData(color: p.text, size: 20),
          child: Center(child: w),
        ),
      ),
    );
    final acts = actions ?? const <Widget>[];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: backgroundColor ?? p.bg,
        floatingActionButton: floatingActionButton,
        body: Stack(
          children: [
            const Positioned.fill(child: LovAmbient()),
            Column(
              children: [
                if (needsAppBar)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, top + 14, 16, 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width:
                              44.0 * math.max(1, acts.length) +
                              8.0 * math.max(0, acts.length - 1),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: leading == null ? null : glass(leading!),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (title != null)
                                Text(
                                  title!,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: lovDisplay(context, size: 20),
                                ),
                              if (subtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: DefaultTextStyle.merge(
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: p.muted,
                                    ),
                                    child: subtitle!,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width:
                              44.0 * math.max(1, acts.length) +
                              8.0 * math.max(0, acts.length - 1),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              for (final (i, a) in acts.indexed) ...[
                                if (i > 0) const SizedBox(width: 8),
                                glass(a),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: SafeArea(
                    top: !needsAppBar,
                    child: Padding(
                      padding: padded
                          ? const EdgeInsets.symmetric(horizontal: LovSpace.lg)
                          : EdgeInsets.zero,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
