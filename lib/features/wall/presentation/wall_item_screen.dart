import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/tokens.dart';
import '../domain/wall_logic.dart';
import '../domain/wall_models.dart';
import '../domain/wall_providers.dart';
import 'wall_reaction_bar.dart';
import 'wall_item_thumbnail.dart';
import 'wall_visuals.dart';

enum _ItemAction { collection, delete }

class WallItemScreen extends ConsumerStatefulWidget {
  const WallItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<WallItemScreen> createState() => _WallItemScreenState();
}

class _WallItemScreenState extends ConsumerState<WallItemScreen> {
  /// Reaction toggles not yet reflected by the server: kind -> wanted "mine".
  final _pending = <WallReactionKind, bool>{};

  /// Per-kind tail of the repository calls, so toggles of one kind reach the
  /// server in tap order. Never completes with an error.
  final _chain = <WallReactionKind, Future<void>>{};

  /// Per-kind toggle counter; only the latest toggle may roll back `_pending`.
  final _generation = <WallReactionKind, int>{};
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _comment.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Drops pending toggles the server now agrees with.
  void _prunePending() {
    if (_pending.isEmpty || !mounted) return;
    final server = ref.read(wallReactionSummaryProvider(widget.itemId));
    bool serverMine(WallReactionKind k) {
      for (final r in server) {
        if (r.kind == k) return r.mine;
      }
      return false;
    }

    setState(() => _pending.removeWhere((k, want) => serverMine(k) == want));
  }

  Future<void> _toggleReaction(
      WallItem item, WallReactionKind kind, List<ReactionCount> shown) async {
    final selfId = ref.read(wallSelfIdProvider);
    if (selfId == null) return;
    final currentlyMine = shown.any((r) => r.kind == kind && r.mine);
    final want = !currentlyMine;
    final generation = (_generation[kind] ?? 0) + 1;
    _generation[kind] = generation;
    setState(() => _pending[kind] = want); // the UI flips instantly
    final repo = ref.read(wallRepositoryProvider);
    final previous = _chain[kind] ?? Future<void>.value();
    final call = previous.then((_) => want
        ? repo.addReaction(
            coupleId: item.coupleId, itemId: item.id, userId: selfId, kind: kind)
        : repo.removeReaction(itemId: item.id, userId: selfId, kind: kind));
    _chain[kind] = call.then<void>((_) {}, onError: (_) {});
    try {
      await call;
    } catch (_) {
      if (!mounted) return;
      // A newer tap on this kind owns the pending entry; don't erase it.
      if (_generation[kind] == generation) {
        setState(() => _pending.remove(kind));
      }
      _snack("Couldn't save your reaction");
    }
  }

  Future<void> _sendComment(WallItem item) async {
    final body = _comment.text.trim();
    final selfId = ref.read(wallSelfIdProvider);
    if (body.isEmpty || selfId == null || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(wallRepositoryProvider).addComment(
          coupleId: item.coupleId, itemId: item.id, userId: selfId, body: body);
      if (!mounted) return;
      _comment.clear();
      HapticFeedback.lightImpact();
    } catch (_) {
      _snack("Couldn't send your comment");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return mounted && (ok ?? false);
  }

  Future<void> _deleteItem(WallItem item) async {
    if (!await _confirm('Delete from our Wall?', 'This removes it for both of you.')) return;
    try {
      await ref.read(wallRepositoryProvider).deleteItem(item);
      if (!mounted) return;
      await Navigator.of(context).maybePop();
    } catch (_) {
      _snack("Couldn't delete it");
    }
  }

  Future<void> _deleteComment(WallComment c) async {
    if (!await _confirm('Delete comment?', 'This removes it for both of you.')) return;
    try {
      await ref.read(wallRepositoryProvider).deleteComment(c.id);
    } catch (_) {
      _snack("Couldn't delete the comment");
    }
  }

  Future<void> _changeCollection(WallItem item) async {
    final picked = await showModalBottomSheet<({WallCollection? value})>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(LovSpace.lg, 0, LovSpace.lg, LovSpace.xl),
        child: Wrap(
          spacing: LovSpace.sm,
          runSpacing: LovSpace.sm,
          children: [
            WallPill(
              label: 'None',
              selected: item.collection == null,
              onTap: () => Navigator.pop(ctx, (value: null)),
            ),
            for (final c in WallCollection.values)
              WallPill(
                label: c.label,
                selected: item.collection == c,
                onTap: () => Navigator.pop(ctx, (value: c)),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await ref.read(wallRepositoryProvider).setCollection(item.id, picked.value);
    } catch (_) {
      _snack("Couldn't change the collection");
    }
  }

  Future<void> _togglePin(WallItem item) async {
    try {
      await ref.read(wallRepositoryProvider).setPinned(item.id, !item.isPinned);
      if (!mounted) return;
      HapticFeedback.selectionClick();
    } catch (_) {
      _snack("Couldn't update the pin");
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wallReactionsProvider, (_, _) => _prunePending());
    final itemAsync = ref.watch(wallItemProvider(widget.itemId));
    return itemAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator.adaptive()),
      ),
      error: (_, _) => const _Gone(message: "Couldn't load this item"),
      data: (item) =>
          item == null ? const _Gone(message: 'This item was removed') : _buildItem(item),
    );
  }

  Widget _buildItem(WallItem item) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selfId = ref.watch(wallSelfIdProvider);
    final nameFor = ref.watch(wallNameForProvider);
    final isMine = item.addedBy == selfId;
    final summary = applyPendingReactions(
        ref.watch(wallReactionSummaryProvider(item.id)), _pending);
    final comments = ref.watch(wallItemCommentsProvider(item.id));
    final note = item.note?.trim();
    final meta = [
      if (item.domain != null) item.domain!,
      'shared by ${nameFor(item.addedBy)}',
      formatWallTime(item.createdAt),
      if (item.collection != null) item.collection!.label,
    ].join(' · ');
    final openLabel = item.source == WallSource.article
        ? 'Open in browser'
        : 'Open in ${item.source.label}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Wall'),
        actions: [
          IconButton(
            tooltip: item.isPinned ? 'Unpin' : 'Pin',
            icon: Icon(item.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            onPressed: () => _togglePin(item),
          ),
          PopupMenuButton<_ItemAction>(
            tooltip: 'More',
            onSelected: (a) => switch (a) {
              _ItemAction.collection => _changeCollection(item),
              _ItemAction.delete => _deleteItem(item),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: _ItemAction.collection, child: Text('Change collection')),
              if (isMine)
                PopupMenuItem(
                  value: _ItemAction.delete,
                  child: Text('Delete', style: TextStyle(color: scheme.error)),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  LovSpace.lg, LovSpace.sm, LovSpace.lg, LovSpace.lg),
              children: [
                if (item.hasMedia)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(LovRadius.lg),
                    child: item.source == WallSource.video
                        ? _WallVideo(item: item)
                        : _WallPhoto(item: item),
                  )
                else if (item.url != null)
                  GestureDetector(
                    onTap: () => openWallLink(context, item.url!),
                    child: Hero(
                      tag: wallHeroTag(item.id),
                      child: WallItemThumbnail(
                        item: item,
                        height: 220,
                        borderRadius: LovRadius.lg,
                      ),
                    ),
                  ),
                const SizedBox(height: LovSpace.md),
                if (item.url != null) Text(item.displayTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: LovSpace.xs),
                Text(meta, style: theme.textTheme.bodySmall),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: LovSpace.md),
                  WallNoteQuote(text: note, large: item.url == null && !item.hasMedia),
                ],
                if (item.url != null && !item.hasMedia) ...[
                  const SizedBox(height: LovSpace.md),
                  OutlinedButton.icon(
                    onPressed: () => openWallLink(context, item.url!),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(openLabel),
                  ),
                ],
                const SizedBox(height: LovSpace.lg),
                WallReactionBar(
                  summary: summary,
                  onToggle: (k) => _toggleReaction(item, k, summary),
                ),
                const SizedBox(height: LovSpace.xl),
                Text(comments.isEmpty ? 'No comments yet' : 'Comments',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: LovSpace.sm),
                for (final c in comments)
                  _CommentBubble(
                    comment: c,
                    name: nameFor(c.authorId),
                    isMine: c.authorId == selfId,
                    onLongPress: c.authorId == selfId ? () => _deleteComment(c) : null,
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  LovSpace.md, LovSpace.sm, LovSpace.md, LovSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _comment,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                      onSubmitted: (_) => _sendComment(item),
                      decoration: InputDecoration(
                        hintText: 'Reply…',
                        filled: true,
                        fillColor: scheme.surfaceContainerLow,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(LovRadius.pill),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: LovSpace.sm),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _sending || _comment.text.trim().isEmpty
                        ? null
                        : () => _sendComment(item),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.name,
    required this.isMine,
    this.onLongPress,
  });

  final WallComment comment;
  final String name;
  final bool isMine;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const r = Radius.circular(14);
    const tight = Radius.circular(4);
    return Padding(
      padding: const EdgeInsets.only(bottom: LovSpace.sm),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text('$name · ${formatWallTime(comment.createdAt)}',
                    style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMine ? scheme.secondary : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.only(
                      topLeft: isMine ? r : tight,
                      topRight: isMine ? tight : r,
                      bottomLeft: r,
                      bottomRight: r,
                    ),
                  ),
                  child: Text(comment.body, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hide_source_rounded,
                size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: LovSpace.md),
            Text(message, style: theme.textTheme.titleMedium),
            const SizedBox(height: LovSpace.sm),
            TextButton(
              onPressed: () => context.go('/home/wall'),
              child: const Text('Back to the Wall'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WallPhoto extends ConsumerWidget {
  const _WallPhoto({required this.item});
  final WallItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(wallSignedUrlProvider(item.mediaPath!));
    return SizedBox(
      height: 360,
      child: url.when(
        data: (u) => Semantics(
          image: true,
          label: 'Photo',
          child: InteractiveViewer(
            child: Image.network(
              u,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => WallThumbnail(source: item.source),
            ),
          ),
        ),
        loading: () => WallThumbnail(source: item.source),
        error: (_, _) => WallThumbnail(source: item.source),
      ),
    );
  }
}

class _WallVideo extends ConsumerWidget {
  const _WallVideo({required this.item});
  final WallItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(wallSignedUrlProvider(item.mediaPath!));
    return SizedBox(
      height: 360,
      child: url.when(
        data: (u) => _VideoPlayer(url: u),
        loading: () => WallThumbnail(source: item.source, showPlay: false),
        error: (_, _) => WallThumbnail(source: item.source, showPlay: false),
      ),
    );
  }
}

class _CantPlay extends StatelessWidget {
  const _CantPlay();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text("Can't play this video",
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70)),
        ),
      );
}

class _VideoPlayer extends StatefulWidget {
  const _VideoPlayer({required this.url});
  final String url;

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer> {
  late final VideoPlayerController _c;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (_c.value.hasError && !_failed && mounted) setState(() => _failed = true);
      })
      ..initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {
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
    if (_failed) return const _CantPlay();
    if (!_c.value.isInitialized) return const ColoredBox(color: Colors.black);
    return Semantics(
      button: true,
      label: _c.value.isPlaying ? 'Pause video' : 'Play video',
      child: GestureDetector(
      onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
            if (!_c.value.isPlaying)
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 64),
          ],
        ),
      ),
    ));
  }
}
