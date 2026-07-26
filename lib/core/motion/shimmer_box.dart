import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'lov_motion.dart';

/// A shape-preserving skeleton placeholder with a slow shimmer.
///
/// Prefer this over CircularProgressIndicator for content-shaped loading.
class LovShimmerBox extends StatefulWidget {
  const LovShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = LovRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<LovShimmerBox> createState() => _LovShimmerBoxState();
}

class _LovShimmerBoxState extends State<LovShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (LovMotion.motionEnabled(context)) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark ? LovColors.surfaceMutedDark : LovColors.surfaceMuted;
    final highlight = isDark ? LovColors.surfaceDark : Colors.white;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment(-1 + t * 2, 0),
                  end: Alignment(0 + t * 2, 0),
                  colors: [
                    base,
                    highlight.withValues(alpha: 0.5),
                    base,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(rect);
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
