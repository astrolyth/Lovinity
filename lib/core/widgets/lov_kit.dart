// The redesign's component layer (website/project/*.dc.html, "v2 component
// layer" + "sheet kit"). Built only from Flutter's own widgets.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../theme/typography.dart';

/// Apple-like spring used for releases and slides (CSS `--spring`).
const lovSpring = Cubic(.2, .9, .25, 1);

/// Overshooting spring (CSS `--bounce`).
const lovBounce = Curves.easeOutBack;

// ---------------------------------------------------------------- text

/// Small uppercase label above a section ("NEXT PRAYER").
class LovEyebrow extends StatelessWidget {
  const LovEyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
      color: color ?? context.lov.muted,
    ),
  );
}

/// Space Grotesk display text (`.disp`).
TextStyle lovDisplay(
  BuildContext context, {
  double size = 20,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? height,
}) => TextStyle(
  fontFamily: LovTypography.display,
  fontSize: size,
  fontWeight: weight,
  height: height,
  letterSpacing: -0.025 * size,
  color: color ?? context.lov.text,
);

/// Amiri Arabic text (`.ar`).
TextStyle lovArabic(BuildContext context, {double size = 22, Color? color}) =>
    TextStyle(
      fontFamily: LovTypography.arabic,
      fontSize: size,
      height: 1.8,
      color: color ?? context.lov.accentInk,
    );

/// Gold → partner gradient sweeping through text (`.shine`).
class LovShineText extends StatefulWidget {
  const LovShineText(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<LovShineText> createState() => _LovShineTextState();
}

class _LovShineTextState extends State<LovShineText>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) {
          final shift = (1.2 - 2.5 * _c.value) * r.width;
          return LinearGradient(
            colors: [p.accent, p.accentHi, p.partner, p.accent],
            stops: const [.3, .46, .62, .8],
            transform: _Slide(shift),
          ).createShader(Rect.fromLTWH(0, 0, r.width * 2.5, r.height));
        },
        child: child,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.dx);
  final double dx;
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

// ---------------------------------------------------------------- motion

/// Instant press-in, springy release (`.scr :is(a,button):active`).
class LovPressable extends StatefulWidget {
  const LovPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = .965,
    this.haptic = false,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<LovPressable> createState() => _LovPressableState();
}

class _LovPressableState extends State<LovPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down && !context.reduceMotion ? widget.scale : 1,
        duration: _down
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 500),
        curve: _down ? Curves.easeOut : lovBounce,
        child: widget.child,
      ),
    );
  }
}

/// Fade + rise entrance with a delay (`.rise`). Off under reduced motion.
class LovRise extends StatefulWidget {
  const LovRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 16),
  });
  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<LovRise> createState() => _LovRiseState();
}

class _LovRiseState extends State<LovRise> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );

  Timer? _start;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _start = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return widget.child;
    final a = CurvedAnimation(parent: _c, curve: lovSpring);
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value.clamp(0, 1),
        child: Transform.translate(
          offset: widget.offset * (1 - a.value),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------- surfaces

/// Card surface: gradient fill, lit hairline border, soft depth (`.card`).
class LovSurface extends StatelessWidget {
  const LovSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 24,
    this.onTap,
    this.clip = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final r = BorderRadius.circular(radius);
    Widget body = Container(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: const Alignment(-.2, -1),
          end: const Alignment(.2, 1),
          colors: [
            p.hi.withValues(alpha: .12),
            p.hi.withValues(alpha: .03),
            p.accent.withValues(alpha: .12),
          ],
          stops: const [0, .42, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: p.shadow.withValues(alpha: .45),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: p.shadow.withValues(alpha: p.isDark ? .9 : .25),
            blurRadius: 34,
            spreadRadius: -18,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: Container(
        clipBehavior: clip ? Clip.antiAlias : Clip.none,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius - 1),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [p.cardA, p.cardB],
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
    if (onTap != null) body = LovPressable(onTap: onTap, child: body);
    return body;
  }
}

/// Feature tile with a tinted glyph (`.tile`). [tint] defaults to accent.
class LovTile extends StatelessWidget {
  const LovTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.tint,
    this.onTap,
    this.height = 108,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? tint;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final t = tint ?? p.accent;
    return Semantics(
      button: true,
      label: [title, ?subtitle].join(', '),
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: LovSurface(
            radius: 20,
            padding: EdgeInsets.zero,
            clip: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-.6, -1),
                        radius: 1.1,
                        colors: [
                          t.withValues(alpha: .14 * .6),
                          t.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      LovGlyph(icon: icon, tint: t),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: p.text,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: subtitleColor ?? p.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded icon well with a tinted radial glow (`.tile .glyph`).
class LovGlyph extends StatelessWidget {
  const LovGlyph({
    super.key,
    required this.icon,
    this.tint,
    this.size = 36,
    this.radius = 12,
  });
  final IconData icon;
  final Color? tint;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = tint ?? context.lov.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: RadialGradient(
          center: const Alignment(-.4, -.6),
          colors: [t.withValues(alpha: .30), t.withValues(alpha: .06)],
          stops: const [0, .75],
        ),
        border: Border.all(color: t.withValues(alpha: .22)),
        boxShadow: [
          BoxShadow(
            color: t.withValues(alpha: .3),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, size: size * .55, color: t),
    );
  }
}

/// Frosted layer (`backdrop-filter: blur() saturate()`).
class LovGlass extends StatelessWidget {
  const LovGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blur = 14,
    this.color,
    this.border,
    this.shadows,
  });
  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color? color;
  final BoxBorder? border;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? p.hi.withValues(alpha: .045),
              borderRadius: borderRadius,
              border: border ?? Border.all(color: p.hi.withValues(alpha: .09)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- controls

/// 44pt round glass icon button (`.iconbtn`), with an optional partner dot.
class LovIconButton extends StatelessWidget {
  const LovIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.dot = false,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool dot;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: LovGlass(
          borderRadius: BorderRadius.circular(999),
          shadows: [
            BoxShadow(
              color: p.shadow.withValues(alpha: p.isDark ? .8 : .15),
              blurRadius: 16,
              spreadRadius: -8,
              offset: const Offset(0, 6),
            ),
          ],
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 20, color: color ?? p.text),
                if (dot)
                  Positioned(
                    top: 10,
                    right: 11,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: p.partner,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold gradient call-to-action with a periodic sheen (`.primary`, `.kbtn.gold`).
class LovPrimaryButton extends StatefulWidget {
  const LovPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final double height;

  @override
  State<LovPrimaryButton> createState() => _LovPrimaryButtonState();
}

class _LovPrimaryButtonState extends State<LovPrimaryButton>
    with SingleTickerProviderStateMixin {
  late final _sheen = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _sheen.stop() : _sheen.repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final enabled = widget.onPressed != null && !widget.loading;
    final fg = enabled ? p.onAccent : p.faint;
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
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -.16,
              color: fg,
            ),
          ),
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
        child: Container(
          height: widget.height,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: enabled ? null : p.surface2,
            border: enabled ? null : Border.all(color: p.line),
            gradient: enabled
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.accentHi, p.accent, p.accentLo],
                    stops: const [0, .48, 1],
                  )
                : null,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: p.accent.withValues(alpha: .7),
                      blurRadius: 30,
                      spreadRadius: -12,
                      offset: const Offset(0, 12),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (enabled)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _sheen,
                    builder: (_, _) {
                      // Sweep across in the first 28% of each 5 s cycle.
                      final t = (_sheen.value / .28).clamp(0.0, 1.0);
                      return FractionalTranslation(
                        translation: Offset(-1.3 + 2.6 * t, 0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: const Alignment(-1, -.2),
                              end: const Alignment(1, .2),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: .35),
                                Colors.white.withValues(alpha: 0),
                              ],
                              stops: const [.38, .5, .62],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              content,
            ],
          ),
        ),
      ),
    );
  }
}

/// Low-emphasis full-width pill (`.kbtn.quiet`, `.ghost`).
class LovQuietButton extends StatelessWidget {
  const LovQuietButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.height = 54,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final fg = color ?? p.text;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: LovPressable(
        onTap: onPressed,
        child: Opacity(
          opacity: onPressed == null ? .4 : 1,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: p.hi.withValues(alpha: .06),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill segmented control with a sliding thumb (Home's Deen / Us / Home).
class LovSegmented<T> extends StatelessWidget {
  const LovSegmented({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.height = 48,
  });
  final List<T> values;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final i = values.indexOf(selected);
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.line),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - 4 * (values.length - 1)) / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 500),
                curve: lovSpring,
                left: i * (w + 4),
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.line,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: p.shadow.withValues(alpha: .35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (j, v) in values.indexed) ...[
                    if (j > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: v == selected,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (v != selected) {
                              HapticFeedback.selectionClick();
                              onChanged(v);
                            }
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              style: TextStyle(
                                fontFamily: LovTypography.body,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: v == selected ? p.text : p.muted,
                              ),
                              child: Text(labelOf(v)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Small pill label, e.g. "12 days together".
class LovPill extends StatelessWidget {
  const LovPill({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
  });
  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final fg = foreground ?? p.accentInk;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: background ?? p.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// You (gold) and your spouse (rose) avatars, overlapped (`.duo`).
class LovDuo extends StatelessWidget {
  const LovDuo({
    super.key,
    required this.self,
    required this.partner,
    this.size = 34,
    this.partnerOnline = false,
  });
  final String self;
  final String partner;
  final double size;
  final bool partnerOnline;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return SizedBox(
      height: 44,
      width: size * 2 - 10,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          LovAvatar(initial: self, size: size),
          Positioned(
            left: size - 10,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                LovAvatar(initial: partner, size: size, partner: true),
                if (partnerOnline)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7BD88F),
                        shape: BoxShape.circle,
                        border: Border.all(color: p.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient initial avatar: gold for you, rose for your spouse.
class LovAvatar extends StatelessWidget {
  const LovAvatar({
    super.key,
    required this.initial,
    this.size = 34,
    this.partner = false,
  });
  final String initial;
  final double size;
  final bool partner;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: p.bg, width: 2.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: partner
              ? [p.partnerHi, p.partnerLo]
              : [p.accentHi, p.accentLo],
        ),
      ),
      child: Text(
        initial.isEmpty ? '·' : initial.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: LovTypography.display,
          fontWeight: FontWeight.w600,
          fontSize: size * .38,
          color: partner ? p.onPartner : p.onAccent,
        ),
      ),
    );
  }
}

/// Rotating gold → rose light running around a rounded border (`.beam`).
class LovBeam extends StatefulWidget {
  const LovBeam({super.key, required this.child, required this.radius});
  final Widget child;
  final double radius;

  @override
  State<LovBeam> createState() => _LovBeamState();
}

class _LovBeamState extends State<LovBeam> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return CustomPaint(
      foregroundPainter: _BeamPainter(
        _c,
        widget.radius,
        p.accent.withValues(alpha: .9),
        p.partner,
      ),
      child: widget.child,
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter(this.t, this.radius, this.a, this.b) : super(repaint: t);
  final Animation<double> t;
  final double radius;
  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(
      rect.deflate(.75),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = SweepGradient(
        transform: GradientRotation(t.value * 2 * math.pi),
        colors: [
          a.withValues(alpha: 0),
          a.withValues(alpha: 0),
          a,
          b,
          b.withValues(alpha: 0),
        ],
        stops: const [0, .7, .84, .92, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.a != a || old.b != b;
}

// ---------------------------------------------------------------- page

/// Drifting gold + rose glow behind every screen (`.scr::before`).
class LovAmbient extends StatefulWidget {
  const LovAmbient({super.key});

  @override
  State<LovAmbient> createState() => _LovAmbientState();
}

class _LovAmbientState extends State<LovAmbient>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _c.stop() : _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight * .65;
          return Stack(
            children: [
              AnimatedBuilder(
                animation: _c,
                builder: (_, child) {
                  final v = Curves.easeInOut.transform(_c.value);
                  return Positioned(
                    left: -c.maxWidth * .3 + c.maxWidth * .07 * v,
                    right: -c.maxWidth * .3 - c.maxWidth * .07 * v,
                    top: -h * .38 + h * .05 * v,
                    height: h,
                    child: Transform.rotate(angle: v * .157, child: child),
                  );
                },
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-.44, -.1),
                            radius: .5,
                            colors: [
                              p.accent.withValues(alpha: .11),
                              p.accent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(.56, -.3),
                            radius: .45,
                            colors: [
                              p.partner.withValues(alpha: .09),
                              p.partner.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A screen in the redesign: themed background, ambient glow, and a sticky
/// frosted header with a back button, centred title and optional action.
class LovPage extends StatelessWidget {
  const LovPage({
    super.key,
    required this.title,
    required this.slivers,
    this.action,
    this.onBack,
    this.showBack = true,
    this.bottomPadding = 40,
    this.floating,
    this.titleWidget,
  });

  final String title;
  final Widget? titleWidget;
  final List<Widget> slivers;
  final Widget? action;
  final VoidCallback? onBack;
  final bool showBack;
  final double bottomPadding;

  /// Pinned over the content at the bottom (composer, primary action).
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: LovAmbient()),
            CustomScrollView(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _LovHeader(
                    top: top,
                    title:
                        titleWidget ??
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: lovDisplay(context, size: 20),
                        ),
                    leading: showBack
                        ? LovIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            label: 'Back',
                            onTap: onBack ?? () => Navigator.maybePop(context),
                          )
                        : null,
                    action: action,
                    palette: p,
                  ),
                ),
                ...slivers,
                SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
              ],
            ),
            ?floating,
          ],
        ),
      ),
    );
  }
}

class _LovHeader extends SliverPersistentHeaderDelegate {
  _LovHeader({
    required this.top,
    required this.title,
    required this.leading,
    required this.action,
    required this.palette,
  });
  final double top;
  final Widget title;
  final Widget? leading;
  final Widget? action;
  final LovPalette palette;

  @override
  double get minExtent => top + 14 + 44 + 12;
  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrink, bool overlaps) {
    final p = palette;
    final scrolled = overlaps || shrink > 0;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        enabled: scrolled,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: scrolled ? p.bg.withValues(alpha: .7) : Colors.transparent,
          padding: EdgeInsets.fromLTRB(16, top + 14, 16, 12),
          child: Row(
            children: [
              SizedBox(width: 44, child: leading),
              const SizedBox(width: 12),
              Expanded(child: title),
              const SizedBox(width: 12),
              SizedBox(width: 44, child: action),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_LovHeader old) =>
      old.top != top ||
      old.title != title ||
      old.action != action ||
      old.leading != leading ||
      old.palette != palette;
}

/// Section eyebrow inside a [LovPage] sliver list.
class LovSectionLabel extends StatelessWidget {
  const LovSectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 28, 20, 10),
    this.trailing,
  });
  final String text;
  final EdgeInsets padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: LovEyebrow(text)),
        ?trailing,
      ],
    ),
  );
}

// ---------------------------------------------------------------- sheet kit

/// The design's bottom sheet: frosted, 30pt corners, grabber, display title.
Future<T?> showLovSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final p = context.lov;
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              34 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: lovDisplay(context, size: 21)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 14, color: p.muted),
                    ),
                  ],
                  const SizedBox(height: 8),
                  builder(context),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Action row inside a sheet (`.krow`): tinted icon well, title, hint.
class LovSheetRow extends StatelessWidget {
  const LovSheetRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.danger = false,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final c = danger ? const Color(0xFFE5534B) : p.accent;
    return Semantics(
      button: onTap != null,
      label: [title, ?subtitle].join(', '),
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        scale: .98,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: c, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: danger ? c : p.text,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12.5, color: p.muted),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's toast: frosted, check icon, optional Undo.
void showLovToast(
  BuildContext context,
  String message, {
  VoidCallback? onUndo,
  IconData icon = Icons.check_circle_outline_rounded,
}) {
  final p = context.lov;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2800),
        content: Row(
          children: [
            Icon(icon, color: p.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        action: onUndo == null
            ? null
            : SnackBarAction(label: 'Undo', onPressed: onUndo),
      ),
    );
}
