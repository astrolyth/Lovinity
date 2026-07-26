import 'package:flutter/widgets.dart';

import 'lov_motion.dart';

/// Wraps a widget in a one-shot entrance animation: fade + subtle y-slide.
///
/// Honors `MediaQuery.disableAnimationsOf`.
class LovEnter extends StatefulWidget {
  const LovEnter({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = LovMotion.gentle,
    this.slideFrom = 12.0,
    this.curve = LovMotion.enter,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double slideFrom;
  final Curve curve;

  @override
  State<LovEnter> createState() => _LovEnterState();
}

class _LovEnterState extends State<LovEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!LovMotion.motionEnabled(context)) {
      // Reduced motion: instant reveal.
      return widget.child;
    }
    final anim = CurvedAnimation(parent: _controller, curve: widget.curve);
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        return Opacity(
          opacity: anim.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * widget.slideFrom),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
