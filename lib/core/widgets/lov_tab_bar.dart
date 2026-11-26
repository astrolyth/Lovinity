import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'lov_kit.dart';

class LovTabItem {
  const LovTabItem(this.icon, this.selectedIcon, this.label, {this.badge = 0});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

/// Floating frosted pill tab bar (design `.nav`, iOS 26 style).
class LovTabBar extends StatelessWidget {
  const LovTabBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });
  final List<LovTabItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottom > 0 ? bottom : 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: p.isDark ? .85 : .2),
              blurRadius: 44,
              spreadRadius: -14,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: p.bg.withValues(alpha: .66),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: p.hi.withValues(alpha: .09)),
              ),
              child: Row(
                children: [
                  for (final (i, item) in items.indexed)
                    Expanded(
                      child: _Tab(
                        item: item,
                        on: i == selected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelect(i);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.on, required this.onTap});
  final LovTabItem item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final color = on ? p.accent : p.muted;
    return Semantics(
      button: true,
      selected: on,
      label: item.badge > 0 ? '${item.label}, ${item.badge} new' : item.label,
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: lovSpring,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: on
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      p.accent.withValues(alpha: .18),
                      p.accent.withValues(alpha: .05),
                    ],
                  )
                : null,
            border: Border.all(
              color: on ? p.accent.withValues(alpha: .2) : Colors.transparent,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    key: ValueKey(on),
                    tween: Tween(begin: on ? .6 : 1, end: 1),
                    duration: const Duration(milliseconds: 700),
                    curve: lovBounce,
                    builder: (_, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: Icon(
                      on ? item.selectedIcon : item.icon,
                      size: 20,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
              if (item.badge > 0)
                Positioned(
                  top: 3,
                  right: 0,
                  left: 28,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.partner,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.cardB, width: 2),
                      ),
                      child: Text(
                        item.badge > 99 ? '99+' : '${item.badge}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: p.onPartner,
                        ),
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
