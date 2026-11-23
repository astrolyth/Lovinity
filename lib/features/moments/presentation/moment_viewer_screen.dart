import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/widgets/lov_kit.dart';
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

  Future<void> _openReplies(Moment m) async {
    _timer.stop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RepliesSheet(moment: m),
    );
    if (mounted) _timer.forward();
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
                    MomentMedia(
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
                              const SizedBox(width: 14),
                              LovAvatar(
                                initial: nameFor(m.senderId),
                                size: 32,
                                partner: m.senderId != self,
                              ),
                              const SizedBox(width: 10),
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
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: IconButton(
                                  tooltip: 'Close',
                                  onPressed: _close,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black26,
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (m.caption != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Text(
                                m.caption!,
                                style:
                                    lovDisplay(
                                      context,
                                      size: 28,
                                      height: 1.2,
                                      color: Colors.white,
                                    ).copyWith(
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black45,
                                          blurRadius: 20,
                                        ),
                                      ],
                                    ),
                              ),
                            ),
                          _ReactionBar(
                            moment: m,
                            onOpenReplies: () => _openReplies(m),
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
/// Shared with the daily vlog, which shows two of these split-screen.
class MomentMedia extends ConsumerWidget {
  const MomentMedia({
    super.key,
    required this.moment,
    this.onReady,
    this.fit = BoxFit.contain,
  });
  final Moment moment;
  final ValueChanged<Duration>? onReady;
  final BoxFit fit;

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
          ? _Video(url: u, onReady: onReady, fit: fit)
          : Image.network(
              u,
              fit: fit,
              frameBuilder: (_, child, frame, sync) {
                if (frame != null || sync) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => onReady?.call(_photoDuration),
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
  const _Video({required this.url, this.onReady, required this.fit});
  final String url;
  final ValueChanged<Duration>? onReady;
  final BoxFit fit;

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
          widget.onReady?.call(_c.value.duration);
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
    final size = _c.value.size;
    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(_c),
        ),
      ),
    );
  }
}

/// Emoji row (tap to toggle yours) with the partner's reactions shown inline,
/// plus a button into the comment thread.
class _ReactionBar extends ConsumerWidget {
  const _ReactionBar({required this.moment, required this.onOpenReplies});
  final Moment moment;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(wallSelfIdProvider);
    final replies = (ref.watch(momentRepliesProvider).asData?.value ?? const [])
        .where((r) => r.momentId == moment.id)
        .toList();
    final comments = replies.where((r) => r.body != null).length;
    final theirs = {
      for (final r in replies)
        if (r.emoji != null && r.authorId != self) r.emoji!,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          for (final e in momentEmojis)
            Builder(
              builder: (context) {
                final mine = replies
                    .where((r) => r.authorId == self && r.emoji == e)
                    .firstOrNull;
                return Semantics(
                  button: true,
                  selected: mine != null,
                  label: 'React $e',
                  child: InkResponse(
                    onTap: self == null
                        ? null
                        : () => ref
                              .read(momentsRepositoryProvider)
                              .toggleReaction(
                                moment: moment,
                                userId: self,
                                emoji: e,
                                existing: mine,
                              )
                              .catchError((_) {}),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: mine != null ? Colors.white30 : Colors.black26,
                        border: theirs.contains(e)
                            ? Border.all(color: Colors.white, width: 1.5)
                            : null,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                );
              },
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: onOpenReplies,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black26,
            ),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(comments == 0 ? 'Reply' : '$comments'),
          ),
        ],
      ),
    );
  }
}

class _RepliesSheet extends ConsumerStatefulWidget {
  const _RepliesSheet({required this.moment});
  final Moment moment;

  @override
  ConsumerState<_RepliesSheet> createState() => _RepliesSheetState();
}

class _RepliesSheetState extends ConsumerState<_RepliesSheet> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final self = ref.read(wallSelfIdProvider);
    final body = _text.text.trim();
    if (self == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(momentsRepositoryProvider)
          .comment(moment: widget.moment, userId: self, body: body);
      _text.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't send — try again")),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final self = ref.watch(wallSelfIdProvider);
    final nameFor = ref.watch(wallNameForProvider);
    final replies = (ref.watch(momentRepliesProvider).asData?.value ?? const [])
        .where((r) => r.momentId == widget.moment.id)
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
            child: replies.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No replies yet',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in replies)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            r.emoji ?? r.body!,
                            style: r.emoji != null
                                ? const TextStyle(fontSize: 22)
                                : null,
                          ),
                          subtitle: Text(
                            '${nameFor(r.authorId)} · '
                            '${DateFormat.jm().format(r.createdAt)}',
                          ),
                          trailing: r.authorId == self
                              ? IconButton(
                                  tooltip: 'Delete reply',
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => ref
                                      .read(momentsRepositoryProvider)
                                      .deleteReply(r.id)
                                      .catchError((_) {}),
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLength: 300,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Reply to this moment…',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Send reply',
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
