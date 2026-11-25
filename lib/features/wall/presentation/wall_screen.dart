import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/platform/share_intake.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../home/domain/home_providers.dart';
import '../domain/link_detect.dart';
import '../domain/wall_models.dart';
import '../domain/wall_providers.dart';
import 'add_to_wall_sheet.dart';
import 'wall_item_card.dart';
import 'wall_visuals.dart';

/// Album bubble look for each collection (design: colored ring covers).
(Color, IconData) wallAlbumStyle(BuildContext context, WallCollection c) {
  final p = context.lov;
  return switch (c) {
    WallCollection.recipes => (p.partner, Icons.restaurant_outlined),
    WallCollection.places => (const Color(0xFFA9D3B0), Icons.place_outlined),
    WallCollection.home => (p.accent, Icons.home_outlined),
    WallCollection.funny => (
      const Color(0xFFF2B6C9),
      Icons.sentiment_very_satisfied_outlined,
    ),
    WallCollection.deen => (const Color(0xFF9DB8E8), Icons.dark_mode_outlined),
  };
}

class WallScreen extends ConsumerStatefulWidget {
  const WallScreen({super.key});

  @override
  ConsumerState<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends ConsumerState<WallScreen> {
  late final WallLastVisit _lastVisit;

  /// Ids whose entrance animation has already been scheduled. Plain
  /// bookkeeping read by [_AnimateOnce] at mount time, so no setState.
  final Set<String> _animatedIds = {};

  /// The first batch of items shown keeps a staggered entrance; anything that
  /// arrives later animates immediately.
  List<String>? _initialBatch;

  /// True while the add sheet is up, so a share that arrives meanwhile
  /// queues instead of stacking a second sheet.
  bool _sheetOpen = false;

  /// True while a post-frame [_consumePendingShare] is scheduled.
  bool _consumeScheduled = false;

  /// The Pinned album bubble: a local view over pinned items.
  bool _pinnedOnly = false;

  @override
  void initState() {
    super.initState();
    // Captured now: `ref` must not be used in dispose().
    _lastVisit = ref.read(wallLastVisitProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the Wall marks everything up to now as seen. Riverpod forbids
    // writing provider state while the tree is being torn down, so defer the
    // write to a microtask (the notifier outlives this widget).
    final lastVisit = _lastVisit;
    scheduleMicrotask(() => unawaited(lastVisit.markNow()));
    super.dispose();
  }

  Future<void> _openSheet({String? initialUrl, String? initialNote}) async {
    _sheetOpen = true;
    await showAddToWallSheet(
      context,
      initialUrl: initialUrl,
      initialNote: initialNote,
    );
    _sheetOpen = false;
    // A share that arrived while the sheet was open opens now.
    if (mounted) _consumePendingShare();
  }

  /// Opens the add sheet for a pending share, but only while the Wall's own
  /// route is on top. When something covers it (the item detail, which an
  /// incoming share's go('/wall') is about to remove together with
  /// anything pushed over it), the share stays pending; [build] re-checks
  /// once the Wall is current again.
  void _consumePendingShare() {
    if (!mounted || _sheetOpen) return;
    if (ModalRoute.isCurrentOf(context) != true) return;
    final share = ref.read(pendingShareProvider);
    if (share == null) return;
    ref.read(pendingShareProvider.notifier).clear();
    final parsed = parseSharedText(share.text);
    _openSheet(initialUrl: parsed.url, initialNote: parsed.note);
  }

  void _openItem(WallItem item) => context.push('/wall/${item.id}');

  void _filter(WallCollection? c, {bool pinned = false}) {
    setState(() => _pinnedOnly = pinned);
    ref.read(wallFilterProvider.notifier).select(c);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when a share arrives and (via isCurrentOf's dependency) when
    // the route above the Wall goes away, so a waiting share opens as soon
    // as the Wall is on top. Consumed after the frame: never navigate
    // mid-build.
    final hasPendingShare = ref.watch(pendingShareProvider) != null;
    if (hasPendingShare &&
        !_consumeScheduled &&
        ModalRoute.isCurrentOf(context) == true) {
      _consumeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _consumeScheduled = false;
        _consumePendingShare();
      });
    }
    final p = context.lov;
    final itemsAsync = ref.watch(filteredWallItemsProvider);
    final all = ref.watch(wallItemsProvider).asData?.value ?? const [];
    final pinned = ref.watch(pinnedWallItemsProvider);
    final filter = ref.watch(wallFilterProvider);
    final nameFor = ref.watch(wallNameForProvider);
    final weekCount = ref.watch(wallSharedThisWeekProvider);
    final unseen = ref.watch(unseenWallItemIdsProvider);
    final ownName =
        ref.watch(ownProfileProvider).asData?.value?.displayName ?? 'You';
    final spouseName = ref.watch(wallSpouseNameProvider) ?? 'your spouse';
    final top = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barTop = (bottomInset > 0 ? bottomInset : 20) + 64;

    // Pinned posts float to the top; the Pinned bubble shows only them.
    final shown = itemsAsync.whenData((items) {
      final list = _pinnedOnly ? pinned : items;
      return [
        ...list.where((e) => e.isPinned),
        ...list.where((e) => !e.isPinned),
      ];
    });
    final firstBatch = shown.asData?.value;
    if (_initialBatch == null && firstBatch != null && firstBatch.isNotEmpty) {
      _initialBatch = [for (final e in firstBatch.take(6)) e.id];
    }
    final initialBatch = _initialBatch ?? const <String>[];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: LovAmbient()),
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LovEyebrow(
                                weekCount == 0
                                    ? 'Shared between you two'
                                    : '$weekCount ${weekCount == 1 ? 'thing' : 'things'} shared this week',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Our wall',
                                style: lovDisplay(context, size: 32),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SizedBox(
                            width: 42,
                            height: 26,
                            child: Stack(
                              children: [
                                LovAvatar(initial: ownName, size: 26),
                                Positioned(
                                  left: 16,
                                  child: LovAvatar(
                                    initial: spouseName,
                                    size: 26,
                                    partner: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (all.isNotEmpty)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 112,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
                        children: [
                          _Album(
                            label: 'All',
                            count: all.length,
                            icon: Icons.dashboard_outlined,
                            colors: [p.text, p.text2],
                            selected: filter == null && !_pinnedOnly,
                            onTap: () => _filter(null),
                          ),
                          _Album(
                            label: 'Pinned',
                            count: pinned.length,
                            icon: Icons.push_pin_outlined,
                            colors: [p.accentInk, p.accent],
                            selected: _pinnedOnly,
                            onTap: () => _filter(null, pinned: true),
                          ),
                          for (final c in WallCollection.values)
                            _Album(
                              label: c.label,
                              count: all.where((e) => e.collection == c).length,
                              icon: wallAlbumStyle(context, c).$2,
                              colors: [
                                wallAlbumStyle(context, c).$1,
                                Color.lerp(
                                  wallAlbumStyle(context, c).$1,
                                  p.onAccent,
                                  .45,
                                )!,
                              ],
                              selected: filter == c && !_pinnedOnly,
                              onTap: () => _filter(c),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 14)),
                ...shown.when(
                  loading: () => [
                    const SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverToBoxAdapter(child: _CardSkeleton()),
                    ),
                  ],
                  error: (_, _) => [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Message(
                        icon: Icons.cloud_off_rounded,
                        title: "Couldn't load the Wall",
                        actionLabel: 'Try again',
                        onAction: () => ref.invalidate(wallItemsProvider),
                      ),
                    ),
                  ],
                  data: (items) => items.isEmpty
                      ? [
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: filter == null && !_pinnedOnly
                                ? _Message(
                                    icon: Icons.auto_awesome_rounded,
                                    title: 'Share your first find',
                                    body:
                                        'Reels, videos, recipes, places, little notes — keep them here, just for the two of you.',
                                    actionLabel: 'Add to our Wall',
                                    onAction: () => _openSheet(),
                                  )
                                : _Message(
                                    icon: Icons.bookmark_border_rounded,
                                    title: _pinnedOnly
                                        ? 'Nothing pinned yet'
                                        : 'Nothing in ${filter!.label} yet',
                                    body: 'Save a link to this album.',
                                  ),
                          ),
                        ]
                      : [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              barTop + 90,
                            ),
                            sliver: SliverList.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 14),
                              // Keyed cards keep their elements when indices
                              // shift.
                              findItemIndexCallback: (key) {
                                if (key is! ValueKey<String>) return null;
                                final i = items.indexWhere(
                                  (e) => e.id == key.value,
                                );
                                return i < 0 ? null : i;
                              },
                              itemBuilder: (context, i) {
                                final item = items[i];
                                final stagger = initialBatch.indexOf(item.id);
                                return _AnimateOnce(
                                  key: ValueKey(item.id),
                                  id: item.id,
                                  animatedIds: _animatedIds,
                                  delay: Duration(
                                    milliseconds: stagger < 0
                                        ? 0
                                        : 50 * stagger,
                                  ),
                                  child: _ConnectedCard(
                                    item: item,
                                    sharerName: nameFor(item.addedBy),
                                    isUnseen: unseen.contains(item.id),
                                    onOpen: () => _openItem(item),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: barTop + 16,
              child: _ComposeBar(
                label: 'Share a link with $spouseName…',
                onTap: () => _openSheet(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Story-style album bubble with a rotating gold → rose ring when selected.
class _Album extends StatelessWidget {
  const _Album({
    required this.label,
    required this.count,
    required this.icon,
    required this.colors,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final IconData icon;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count links',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: LovPressable(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 62,
            child: Column(
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: _Ring(on: selected)),
                      Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: AnimatedScale(
                          scale: selected ? .94 : 1,
                          duration: const Duration(milliseconds: 500),
                          curve: lovBounce,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: p.bg, width: 2.5),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: colors,
                              ),
                            ),
                            child: Center(
                              child: Icon(icon, size: 22, color: p.onAccent),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: Container(
                          height: 20,
                          constraints: const BoxConstraints(minWidth: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: p.bg, width: 2),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: selected ? p.text : p.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatefulWidget {
  const _Ring({required this.on});
  final bool on;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Ring old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.on && context.allowLoops) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    if (!widget.on) {
      return DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.line),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            transform: GradientRotation(_c.value * 2 * math.pi),
            colors: [p.accent, p.partner, p.accent],
          ),
        ),
      ),
    );
  }
}

/// Frosted "Share a link…" bar floating above the tab bar.
class _ComposeBar extends StatelessWidget {
  const _ComposeBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Tooltip(
      message: 'Add to our Wall',
      child: LovPressable(
        onTap: onTap,
        child: LovGlass(
          borderRadius: BorderRadius.circular(999),
          blur: 20,
          color: p.surface.withValues(alpha: .72),
          shadows: [
            BoxShadow(
              color: p.shadow.withValues(alpha: p.isDark ? .9 : .2),
              blurRadius: 34,
              spreadRadius: -16,
              offset: const Offset(0, 16),
            ),
          ],
          child: SizedBox(
            height: 54,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 7, 0),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 20, color: p.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: p.muted,
                      ),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [p.accentHi, p.accentLo],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: p.accent.withValues(alpha: .7),
                          blurRadius: 20,
                          spreadRadius: -8,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(Icons.add_rounded, color: p.onAccent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Plays the entrance animation the first time [id] is ever built, then never
/// again: a card that is recreated (scrolled off and back, or re-mounted) is
/// shown as-is. The decision is made once, in initState, so rebuilds of a
/// mounted card never swap its widget type.
class _AnimateOnce extends StatefulWidget {
  const _AnimateOnce({
    super.key,
    required this.id,
    required this.animatedIds,
    required this.delay,
    required this.child,
  });
  final String id;
  final Set<String> animatedIds;
  final Duration delay;
  final Widget child;
  @override
  State<_AnimateOnce> createState() => _AnimateOnceState();
}

class _AnimateOnceState extends State<_AnimateOnce> {
  late final bool _animate = widget.animatedIds.add(widget.id);
  @override
  Widget build(BuildContext context) => _animate
      ? LovEnter(delay: widget.delay, child: widget.child)
      : widget.child;
}

class _ConnectedCard extends ConsumerWidget {
  const _ConnectedCard({
    required this.item,
    required this.sharerName,
    required this.isUnseen,
    required this.onOpen,
  });
  final WallItem item;
  final String sharerName;
  final bool isUnseen;
  final VoidCallback onOpen;

  Future<void> _guard(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {
      if (context.mounted) {
        showLovToast(context, "Couldn't save that", icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(wallSelfIdProvider);
    final nameFor = ref.watch(wallNameForProvider);
    final reactions = ref.watch(wallReactionSummaryProvider(item.id));
    final comments = ref.watch(wallItemCommentsProvider(item.id));
    final repo = ref.read(wallRepositoryProvider);
    final last = comments.lastOrNull;
    return WallItemCard(
      item: item,
      sharerName: sharerName,
      isMine: item.addedBy == self,
      avatarName: item.addedBy == self
          ? ref.watch(ownProfileProvider).asData?.value?.displayName
          : null,
      reactions: reactions,
      commentCount: comments.length,
      lastComment: last == null
          ? null
          : WallCommentPreview(author: nameFor(last.authorId), body: last.body),
      isUnseen: isUnseen,
      onOpen: onOpen,
      onOpenLink: item.url == null
          ? null
          : () => openWallLink(context, item.url!),
      onTogglePin: () =>
          _guard(context, () => repo.setPinned(item.id, !item.isPinned)),
      onReact: self == null
          ? null
          : (kind) {
              final mine = reactions.where((r) => r.mine).map((r) => r.kind);
              _guard(context, () async {
                // One reaction each: swap out the old one, or toggle off.
                for (final k in mine) {
                  await repo.removeReaction(
                    itemId: item.id,
                    userId: self,
                    kind: k,
                  );
                }
                if (!mine.contains(kind)) {
                  await repo.addReaction(
                    coupleId: item.coupleId,
                    itemId: item.id,
                    userId: self,
                    kind: kind,
                  );
                }
              });
            },
      onSave: () => _saveTo(context, ref),
    );
  }

  void _saveTo(BuildContext context, WidgetRef ref) {
    final all = ref.read(wallItemsProvider).asData?.value ?? const [];
    showLovSheet<void>(
      context,
      title: 'Save to album',
      builder: (sheet) => Column(
        children: [
          for (final c in WallCollection.values)
            LovSheetRow(
              icon: wallAlbumStyle(context, c).$2,
              title: c.label,
              subtitle: '${all.where((e) => e.collection == c).length} links',
              trailing: item.collection == c
                  ? Icon(Icons.check_rounded, color: context.lov.accent)
                  : null,
              onTap: () {
                Navigator.pop(sheet);
                final prev = item.collection;
                final repo = ref.read(wallRepositoryProvider);
                _guard(context, () => repo.setCollection(item.id, c));
                showLovToast(
                  context,
                  'Saved to ${c.label}',
                  onUndo: () => repo.setCollection(item.id, prev),
                );
              },
            ),
          if (item.collection != null)
            LovSheetRow(
              icon: Icons.bookmark_remove_outlined,
              title: 'Remove from ${item.collection!.label}',
              onTap: () {
                Navigator.pop(sheet);
                _guard(
                  context,
                  () => ref
                      .read(wallRepositoryProvider)
                      .setCollection(item.id, null),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton() : super(key: const Key('wall-skeleton'));

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LovShimmerBox(height: 190, radius: 26),
        SizedBox(height: 10),
        LovShimmerBox(width: 220, height: 14),
        SizedBox(height: 6),
        LovShimmerBox(width: 120, height: 10),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 180),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LovGlyph(icon: icon, size: 72, radius: 24),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: lovDisplay(context, size: 21),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: p.muted),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 22),
            LovPrimaryButton(
              label: actionLabel!,
              expand: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
