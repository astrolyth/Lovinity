import 'package:flutter/widgets.dart';

import 'enter.dart';
import 'lov_motion.dart';

/// Wraps a list of children so each enters with an incremental delay.
///
///     LovStagger(
///       stagger: Duration(milliseconds: 60),
///       children: [Text('A'), Text('B'), Text('C')],
///     )
class LovStagger extends StatelessWidget {
  const LovStagger({
    super.key,
    required this.children,
    this.stagger = const Duration(milliseconds: 60),
    this.initialDelay = Duration.zero,
    this.duration = LovMotion.gentle,
    this.slideFrom = 12.0,
    this.axis = Axis.vertical,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final Duration stagger;
  final Duration initialDelay;
  final Duration duration;
  final double slideFrom;
  final Axis axis;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final wrapped = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      wrapped.add(
        LovEnter(
          key: ValueKey('stagger_$i'),
          delay: initialDelay + stagger * i,
          duration: duration,
          slideFrom: slideFrom,
          child: children[i],
        ),
      );
    }
    if (axis == Axis.horizontal) {
      return Row(
        crossAxisAlignment: crossAxisAlignment,
        children: wrapped,
      );
    }
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: wrapped,
    );
  }
}
