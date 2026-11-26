import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/lov_kit.dart';

/// First screen for a signed-out visitor: the emblem, what Lovinity is for,
/// and the two ways in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final pad = MediaQuery.paddingOf(context);
    final cream = p.accentInk;
    final rowA = [
      ('Prayer log', p.accent),
      ('Tasbih together', p.accent),
      ('Evening adhkar', cream),
      ('Sealed letters', p.partner),
      ('Daily moments', p.partner),
      ('Shared wall', cream),
    ];
    final rowB = [
      ('Encrypted chat', p.partner),
      ('Verse of the day', p.accent),
      ('Love map', p.partner),
      ('Meal plan', cream),
      ('Cycle care', p.partner),
      ('Duas for two', p.accent),
    ];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: _Sky()),
            Padding(
              padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  LovRise(
                    delay: const Duration(milliseconds: 100),
                    child: LovBeam(
                      radius: 999,
                      child: LovGlass(
                        borderRadius: BorderRadius.circular(999),
                        blur: 12,
                        color: p.surface.withValues(alpha: .6),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.dark_mode_outlined,
                                size: 14,
                                color: p.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Made for Muslim couples',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: p.text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const LovEmblem(),
                        const SizedBox(height: 22),
                        const _Title(),
                        const SizedBox(height: 14),
                        LovRise(
                          delay: const Duration(seconds: 1),
                          child: Column(
                            children: [
                              Text(
                                'A private space for the two of you to',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.45,
                                  color: p.text2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const _Rotator(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  LovRise(
                    delay: const Duration(milliseconds: 1200),
                    child: ExcludeSemantics(
                      child: Column(
                        children: [
                          _Marquee(chips: rowA),
                          const SizedBox(height: 8),
                          _Marquee(chips: rowB, reverse: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  LovRise(
                    delay: const Duration(milliseconds: 1350),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        children: [
                          LovPrimaryButton(
                            label: 'Create your space',
                            height: 56,
                            onPressed: () => context.push('/auth/sign-up'),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => context.push('/auth/sign-in'),
                              child: const Text('I already have an account'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 13,
                                color: p.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Messages are end-to-end encrypted',
                                style: TextStyle(fontSize: 12, color: p.muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drifting gold, rose and amber light with twinkling stars.
class _Sky extends StatefulWidget {
  const _Sky();

  @override
  State<_Sky> createState() => _SkyState();
}

class _SkyState extends State<_Sky> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 22),
  );
  final _stars = List.generate(26, (i) {
    final r = math.Random(i * 7919);
    return (r.nextDouble(), r.nextDouble() * .62, r.nextDouble());
  });

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
    Widget blob(double w, double h, Color c, double o) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.withValues(alpha: o),
      ),
    );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = Curves.easeInOut.transform(_c.value);
          return Stack(
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: Stack(
                  children: [
                    Positioned(
                      left: -120 + 30 * v,
                      top: 120 + 20 * v,
                      child: blob(340, 300, p.accent, .22),
                    ),
                    Positioned(
                      right: -130 + 24 * v,
                      top: 60 - 16 * v,
                      child: blob(300, 300, p.partner, .22),
                    ),
                    Positioned(
                      left: -20 - 20 * v,
                      top: 330 + 10 * v,
                      child: blob(420, 220, const Color(0xFF8A5A2B), .25),
                    ),
                  ],
                ),
              ),
              for (final (x, y, phase) in _stars)
                Align(
                  alignment: Alignment(x * 2 - 1, y * 2 - 1),
                  child: Opacity(
                    opacity:
                        .15 +
                        .75 * (.5 + .5 * math.sin((v * 6 + phase) * math.pi)),
                    child: Container(
                      width: 2,
                      height: 2,
                      decoration: BoxDecoration(
                        color: p.accentInk,
                        shape: BoxShape.circle,
                      ),
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

/// Two rings drawn in — you (gold) and your spouse (rose) — with a crescent
/// where they overlap and two orbiting initials.
class LovEmblem extends StatefulWidget {
  const LovEmblem({super.key});

  @override
  State<LovEmblem> createState() => _LovEmblemState();
}

class _LovEmblemState extends State<LovEmblem> with TickerProviderStateMixin {
  late final _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();
  late final _orbit = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _orbit.stop() : _orbit.repeat();
  }

  @override
  void dispose() {
    _draw.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return SizedBox(
      width: 240,
      height: 160,
      child: AnimatedBuilder(
        animation: Listenable.merge([_draw, _orbit]),
        builder: (_, _) => CustomPaint(
          painter: _EmblemPainter(
            draw: context.reduceMotion ? 1 : lovSpring.transform(_draw.value),
            orbit: _orbit.value,
            p: p,
          ),
        ),
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter({required this.draw, required this.orbit, required this.p});
  final double draw;
  final double orbit;
  final LovPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    const a = Offset(95, 80), b = Offset(145, 80);
    const r = 56.0;
    // The overlap, lit like a lens.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: a, radius: r)));
    canvas.drawCircle(
      b,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            p.accentInk.withValues(alpha: .9 * draw),
            p.accent.withValues(alpha: .45 * draw),
            p.accent.withValues(alpha: .25 * draw),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: b, radius: r)),
    );
    canvas.restore();
    void ring(Offset c, Color from, Color to, double t) {
      final rect = Rect.fromCircle(center: c, radius: r);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * t.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [from, to]).createShader(rect),
      );
    }

    ring(a, p.accentInk, p.accent, draw * 1.1);
    ring(b, p.partnerHi, p.partner, draw * 1.1 - .1);
    // Crescent in the lens.
    final moon = Path()
      ..addOval(Rect.fromCircle(center: const Offset(124, 80), radius: 12));
    final bite = Path()
      ..addOval(Rect.fromCircle(center: const Offset(130, 76), radius: 10));
    canvas.drawPath(
      Path.combine(PathOperation.difference, moon, bite),
      Paint()..color = p.bg.withValues(alpha: .85 * draw),
    );
    void orb(Offset center, double angle, Color fill, Color ink, String t) {
      final pos = center + Offset(math.sin(angle) * r, -math.cos(angle) * r);
      canvas.drawCircle(pos, 9, Paint()..color = fill.withValues(alpha: draw));
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            fontFamily: LovTypography.display,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: ink.withValues(alpha: draw),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    orb(a, orbit * 2 * math.pi, p.accent, p.onAccent, '');
    orb(b, math.pi - orbit * 2 * math.pi, p.partner, p.onPartner, '');
  }

  @override
  bool shouldRepaint(_EmblemPainter old) =>
      old.draw != draw || old.orbit != orbit || old.p != p;
}

/// "Lovinity", letter by letter, rising out of a blur.
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final style = lovDisplay(context, size: 52, height: 1).copyWith(
      shadows: [Shadow(color: p.accent.withValues(alpha: .35), blurRadius: 30)],
    );
    return Semantics(
      header: true,
      label: 'Lovinity',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, ch) in 'Lovinity'.characters.indexed)
            LovRise(
              delay: Duration(milliseconds: 300 + 70 * i),
              offset: const Offset(0, 18),
              child: Text(ch, style: style),
            ),
        ],
      ),
    );
  }
}

/// Cycles through what the space is for, one phrase every three seconds.
class _Rotator extends StatefulWidget {
  const _Rotator();

  @override
  State<_Rotator> createState() => _RotatorState();
}

class _RotatorState extends State<_Rotator> {
  static const _phrases = [
    'pray together',
    'write sealed letters',
    'share daily moments',
    'count tasbih as one',
  ];
  int _i = 0;
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _t?.cancel();
    if (context.allowLoops) {
      _t = Timer.periodic(const Duration(seconds: 3), (_) {
        if (mounted) setState(() => _i = (_i + 1) % _phrases.length);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, .5),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: lovSpring)),
            child: child,
          ),
        ),
        child: LovShineText(
          _phrases[_i],
          key: ValueKey(_i),
          style: lovDisplay(context, size: 22),
        ),
      ),
    );
  }
}

/// A row of feature chips gliding sideways, faded at both edges.
class _Marquee extends StatefulWidget {
  const _Marquee({required this.chips, this.reverse = false});
  final List<(String, Color)> chips;
  final bool reverse;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 38),
  );
  final _key = GlobalKey();
  double _w = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _c.stop() : _c.repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && mounted) setState(() => _w = box.size.width + 8);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    Widget row({Key? key}) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, (t, c)) in widget.chips.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: p.hi.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.hi.withValues(alpha: .08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: c, blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 7),
                Text(t, style: TextStyle(fontSize: 13, color: p.text2)),
              ],
            ),
          ),
        ],
      ],
    );
    return SizedBox(
      height: 34,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, .14, .86, 1],
        ).createShader(r),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, child) {
                final t = widget.reverse ? 1 - _c.value : _c.value;
                return Transform.translate(
                  offset: Offset(-_w * t, 0),
                  child: child,
                );
              },
              child: Row(
                children: [
                  row(key: _key),
                  const SizedBox(width: 8),
                  row(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
