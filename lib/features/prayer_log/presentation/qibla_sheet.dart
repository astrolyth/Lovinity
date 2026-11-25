import 'dart:math' as math;

import 'package:adhan/adhan.dart' as adhan;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../home/domain/home_providers.dart';

/// Compass bearing (degrees clockwise from true north) to the Kaaba.
double qiblaBearing(double latitude, double longitude) =>
    adhan.Qibla(adhan.Coordinates(latitude, longitude)).direction;

/// "NE", "SW", ... for a bearing in degrees.
String compassPoint(double deg) =>
    const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][((deg % 360) / 45)
            .round() %
        8];

Future<void> showQiblaSheet(BuildContext context) => showLovSheet<void>(
  context,
  title: 'Qibla',
  builder: (_) => const _QiblaView(),
);

class _QiblaView extends ConsumerStatefulWidget {
  const _QiblaView();

  @override
  ConsumerState<_QiblaView> createState() => _QiblaViewState();
}

class _QiblaViewState extends ConsumerState<_QiblaView> {
  bool _wasAligned = false;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final profile = ref.watch(ownProfileProvider).asData?.value;
    if (profile?.latitude == null || profile?.longitude == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Set your location on Home to find the Qibla.',
          style: TextStyle(fontSize: 14, color: p.muted),
        ),
      );
    }
    final qibla = qiblaBearing(profile!.latitude!, profile.longitude!);
    final label =
        'Qibla is ${qibla.round()} degrees ${compassPoint(qibla)} of north';

    return StreamBuilder<CompassEvent>(
      // Null on devices without a magnetometer: show the bearing only.
      stream: FlutterCompass.events,
      builder: (context, snap) {
        final heading = snap.data?.heading;
        final off = heading == null
            ? null
            : ((qibla - heading + 540) % 360) - 180; // -180..180
        final aligned = off != null && off.abs() < 5;
        if (aligned && !_wasAligned) HapticFeedback.mediumImpact();
        _wasAligned = aligned;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Semantics(
              label: label,
              image: true,
              child: SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedRotation(
                      // Turn the dial against the phone so north stays north.
                      turns: -(heading ?? 0) / 360,
                      duration: const Duration(milliseconds: 200),
                      child: CustomPaint(
                        size: const Size.square(260),
                        painter: _DialPainter(
                          qibla: qibla,
                          line: p.line,
                          text: p.muted,
                          accent: p.accent,
                        ),
                      ),
                    ),
                    // The phone's facing direction: a fixed marker at the top.
                    Positioned(
                      top: 0,
                      child: Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 36,
                        color: aligned ? p.accent : p.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: aligned
                  ? Row(
                      key: const ValueKey('aligned'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, color: p.accent, size: 20),
                        const SizedBox(width: 6),
                        Text(
                          'Facing the Qibla',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: p.accent,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      heading == null
                          ? '${qibla.round()}° ${compassPoint(qibla)} from north'
                          : 'Turn until the Kaaba is at the top',
                      key: ValueKey(heading == null),
                      style: TextStyle(fontSize: 15, color: p.text2),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              'Hold your phone flat, away from metal.',
              style: TextStyle(fontSize: 12, color: p.faint),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.qibla,
    required this.line,
    required this.text,
    required this.accent,
  });
  final double qibla;
  final Color line, text, accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 18;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = line,
    );
    Offset at(double deg, double radius) {
      final a = (deg - 90) * math.pi / 180;
      return c + Offset(math.cos(a), math.sin(a)) * radius;
    }

    for (var d = 0; d < 360; d += 15) {
      canvas.drawLine(
        at(d.toDouble(), r - (d % 90 == 0 ? 12 : 6)),
        at(d.toDouble(), r),
        Paint()
          ..strokeWidth = d % 90 == 0 ? 2 : 1
          ..color = text,
      );
    }
    for (final (d, l) in [(0, 'N'), (90, 'E'), (180, 'S'), (270, 'W')]) {
      final tp = TextPainter(
        text: TextSpan(
          text: l,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at(d.toDouble(), r - 26) - tp.size.center(Offset.zero));
    }
    // Needle to the Kaaba, ending in a small square.
    canvas.drawLine(
      c,
      at(qibla, r - 30),
      Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
    canvas.drawRect(
      Rect.fromCenter(center: at(qibla, r - 30), width: 16, height: 16),
      Paint()..color = accent,
    );
    canvas.drawCircle(c, 5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.qibla != qibla || old.accent != accent || old.line != line;
}
