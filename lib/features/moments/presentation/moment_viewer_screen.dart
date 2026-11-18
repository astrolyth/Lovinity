import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../wall/domain/wall_providers.dart';
import '../domain/moment.dart';
import '../domain/moments_providers.dart';

const _photoDuration = Duration(seconds: 5);

/// Full-screen, stories-style: tap right = next (newer), left = previous,
/// hold = pause, swipe down = close. Photos hold 5 s, videos play through.
class MomentViewerScreen extends ConsumerStatefulWidget {
  const MomentViewerScreen({super.key, required this.momentId});
  final String momentId;

  @override
  ConsumerState<MomentViewerScreen> createState() => _MomentViewerScreenState();
}

class _MomentViewerScreenState extends ConsumerState<MomentViewerScreen>
    with SingleTickerProviderStateMixin {
  late String _currentId = widget.momentId;
  String? _startedFor;
  late final AnimationController _timer = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _step(1);
    });
  final _marked = <String>{};

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  void _close() => context.canPop() ? context.pop() : context.go('/moments');

  /// +1 = forward in time (newer). The list is newest-first.
  void _step(int delta) {
    final list = ref.read(momentsProvider).asData?.value ?? const [];
    final i = list.indexWhere((m) => m.id == _currentId) - delta;
    if (i < 0 || i >= list.length) return _close();
    _timer.reset();
    setState(() => _currentId = list[i].id);
  }

  /// Media is on screen: mark it seen and start its progress bar, once per moment.
  void _ready(Moment m, Duration d) {
    if (!mounted || _startedFor == m.id) return;
    _startedFor = m.id;
    _timer
      ..duration = d
      ..forward(from: 0);
    final self = ref.read(wallSelfIdProvider);
    if (m.senderId == self || m.viewedAt != null || !_marked.add(m.id)) return;
    ref.read(momentsRepositoryProvider).markViewed(m.id).catchError((_) {
      _marked.remove(m.id); // retry next time it's shown
    });
  }

  Future<void> _delete(Moment m) async {
    _timer.stop();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this moment?'),
        content: const Text('It will disappear for both of you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) {
      _timer.forward();
      return;
    }
    try {
      await ref.read(momentsRepositoryProvider).delete(m);
      if (mounted) _close();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete — try again")),
      );
      _timer.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(momentsProvider).asData?.value;
    final m = list?.where((x) => x.id == _currentId).firstOrNull;
    final self = ref.watch(wallSelfIdProvider);
    final nameFor = ref.watch(wallNameForProvider);
    const shadow = [Shadow(blurRadius: 8)];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: m == null
            ? Center(
                child: list == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : TextButton(
                        onPressed: _close,
                        child: const Text('This moment is gone'),
                      ),
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _step(
                  d.localPosition.dx < MediaQuery.sizeOf(context).width / 3
                      ? -1
                      : 1,
                ),
                onLongPressStart: (_) => _timer.stop(),
                onLongPressEnd: (_) => _timer.forward(),
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 300) _close();
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Media(
                      key: ValueKey(m.id),
                      moment: m,
                      onReady: (d) => _ready(m, d),
                    ),
                    SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: AnimatedBuilder(
                              animation: _timer,
                              builder: (_, _) => LinearProgressIndicator(
                                value: _timer.value,
                                minHeight: 3,
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  '${nameFor(m.senderId)} · '
                                  '${DateFormat.jm().format(m.createdAt)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    shadows: shadow,
                                  ),
                                ),
                              ),
                              if (m.senderId == self)
                                IconButton(
                                  tooltip: 'Delete moment',
                                  onPressed: () => _delete(m),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.white,
                                  ),
                                ),
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
                          const Spacer(),
                          if (m.caption != null)
                            Container(
                              width: double.infinity,
                              color: Colors.black45,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 24),
                              child: Text(
                                m.caption!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          if (m.senderId == self)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                m.viewedAt == null
                                    ? 'Delivered'
                                    : 'Seen ${DateFormat.jm().format(m.viewedAt!)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  shadows: shadow,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Loads the signed URL and reports when the media is on screen.
class _Media extends ConsumerWidget {
  const _Media({super.key, required this.moment, required this.onReady});
  final Moment moment;
  final ValueChanged<Duration> onReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const spinner = Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
    final url = ref.watch(momentSignedUrlProvider(moment.mediaPath));
    return url.when(
      loading: () => spinner,
      error: (_, _) => const _Failed(),
      data: (u) => moment.isVideo
          ? _Video(url: u, onReady: onReady)
          : Image.network(
              u,
              fit: BoxFit.contain,
              frameBuilder: (_, child, frame, sync) {
                if (frame != null || sync) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => onReady(_photoDuration),
                  );
                }
                return child;
              },
              loadingBuilder: (_, child, p) => p == null ? child : spinner,
              errorBuilder: (_, _, _) => const _Failed(),
            ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed();
  @override
  Widget build(BuildContext context) => const Center(
    child: Text(
      "Can't load this moment",
      style: TextStyle(color: Colors.white70),
    ),
  );
}

class _Video extends StatefulWidget {
  const _Video({required this.url, required this.onReady});
  final String url;
  final ValueChanged<Duration> onReady;

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(
    Uri.parse(widget.url),
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _c
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _c.play();
          widget.onReady(_c.value.duration);
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const _Failed();
    if (!_c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _c.value.aspectRatio,
        child: VideoPlayer(_c),
      ),
    );
  }
}
