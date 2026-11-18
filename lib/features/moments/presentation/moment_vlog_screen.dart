import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../wall/domain/wall_providers.dart';
import '../domain/moment.dart';
import '../domain/moments_providers.dart';
import 'moment_viewer_screen.dart';

/// The day's vlog: every hour's moments, oldest first, split-screen —
/// partner on top, you below. Each slot plays for the clip length (3 s).
class MomentVlogScreen extends ConsumerStatefulWidget {
  const MomentVlogScreen({super.key, required this.day});

  /// yyyy-MM-dd of the vlog day (which closes at 4am).
  final String day;

  @override
  ConsumerState<MomentVlogScreen> createState() => _MomentVlogScreenState();
}

class _MomentVlogScreenState extends ConsumerState<MomentVlogScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _done = false;
  late final AnimationController _timer =
      AnimationController(vsync: this, duration: maxMomentVideo)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _go(_index + 1);
        })
        ..forward();

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  List<VlogSlot> _slots() {
    final day = DateTime.tryParse(widget.day);
    if (day == null) return const [];
    final self = ref.read(wallSelfIdProvider) ?? '';
    final all = ref.read(momentsProvider).asData?.value ?? const [];
    return vlogSlots([
      for (final m in all)
        if (vlogDay(m.createdAt) == day) m,
    ], self);
  }

  void _go(int i) {
    if (i >= _slots().length) {
      setState(() => _done = true);
      return;
    }
    setState(() {
      _index = i < 0 ? 0 : i;
      _done = false;
    });
    _timer.forward(from: 0);
  }

  void _close() => context.canPop() ? context.pop() : context.go('/moments');

  @override
  Widget build(BuildContext context) {
    ref.watch(momentsProvider); // rebuild when moments arrive
    final slots = _slots();
    final nameFor = ref.watch(wallNameForProvider);
    final spouseLabel = ref.watch(wallSpouseNameProvider) ?? 'Partner';
    final day = DateTime.tryParse(widget.day);
    const shadow = [Shadow(blurRadius: 8)];

    Widget panel(Moment? m, String who) => Expanded(
      child: m == null
          ? ColoredBox(
              color: const Color(0xFF151515),
              child: Center(
                child: Text(
                  '$who — no moment this hour',
                  style: const TextStyle(color: Colors.white38),
                ),
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                MomentMedia(
                  key: ValueKey('${m.id}-$_index'),
                  moment: m,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    [nameFor(m.senderId), ?m.caption].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      shadows: shadow,
                    ),
                  ),
                ),
              ],
            ),
    );

    Widget body() {
      if (slots.isEmpty) {
        return Center(
          child: TextButton(
            onPressed: _close,
            child: const Text('No moments this day'),
          ),
        );
      }
      if (_done) {
        return _End(
          onReplay: () => _go(0),
          onClose: _close,
          title: day == null
              ? 'That was the day'
              : 'That was ${DateFormat.MMMEd().format(day)}',
        );
      }
      final slot = slots[_index.clamp(0, slots.length - 1)];
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _go(
          d.localPosition.dx < MediaQuery.sizeOf(context).width / 3
              ? _index - 1
              : _index + 1,
        ),
        onLongPressStart: (_) => _timer.stop(),
        onLongPressEnd: (_) => _timer.forward(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) _close();
        },
        child: Stack(
          children: [
            Column(
              children: [
                panel(slot.partner, spouseLabel),
                const SizedBox(height: 2),
                panel(slot.mine, 'You'),
              ],
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: AnimatedBuilder(
                      animation: _timer,
                      builder: (_, _) => Row(
                        children: [
                          for (var i = 0; i < slots.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                child: LinearProgressIndicator(
                                  value: i < _index
                                      ? 1
                                      : i == _index
                                      ? _timer.value
                                      : 0,
                                  minHeight: 3,
                                  color: Colors.white,
                                  backgroundColor: Colors.white24,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      Text(
                        DateFormat.j().format(slot.hour),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          shadows: shadow,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: _close,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(backgroundColor: Colors.black, body: body()),
    );
  }
}

class _End extends StatelessWidget {
  const _End({
    required this.onReplay,
    required this.onClose,
    required this.title,
  });
  final VoidCallback onReplay;
  final VoidCallback onClose;
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onReplay,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Watch again'),
        ),
        TextButton(
          onPressed: onClose,
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
