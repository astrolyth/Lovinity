import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'lov_motion.dart';

/// A thin circular arc that shrinks as time runs out. Turns to [warningColor]
/// under the last minute.
class CountdownRing extends StatefulWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 200,
    this.strokeWidth = 2,
    this.color,
    this.warningColor,
    this.child,
  });

  final Duration remaining;
  final Duration total;
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? warningColor;
  final Widget? child;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.color ?? theme.colorScheme.primary.withValues(alpha: 0.4);
    final warning = widget.warningColor ?? theme.colorScheme.error;

    final fraction = widget.total.inMilliseconds == 0
        ? 0.0
        : (widget.remaining.inMilliseconds / widget.total.inMilliseconds)
            .clamp(0.0, 1.0);

    final isUrgent = widget.remaining.inSeconds > 0 &&
        widget.remaining.inSeconds < 60;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: fraction, end: fraction),
            duration: LovMotion.gentle,
            curve: LovMotion.standardCurve,
            builder: (context, value, _) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingPainter(
                fraction: value,
                strokeWidth: widget.strokeWidth,
                color: isUrgent ? warning : color,
                trackColor: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          if (widget.child != null)
            Padding(
              padding: const EdgeInsets.all(LovSpace.xl),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double fraction;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // start at 12 o'clock
      2 * math.pi * fraction,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
