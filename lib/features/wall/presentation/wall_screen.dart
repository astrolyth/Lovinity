import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../home/domain/home_providers.dart';
import '../domain/wall_models.dart';
import '../domain/wall_providers.dart';
import 'add_to_wall_sheet.dart';
import 'wall_item_card.dart';
import 'wall_pinned_row.dart';
import 'wall_visuals.dart';

class WallScreen extends ConsumerStatefulWidget {
  const WallScreen({super.key});

  @override
  ConsumerState<WallScreen> createState() => _WallScreenState();
}

class _WallScreenState extends ConsumerState<WallScreen> {
  late final WallLastVisit _lastVisit;

  @override
  void initState() {
    super.initState();
    // Captured now: `ref` must not be used in dispose().
    _lastVisit = ref.read(wallLastVisitProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the Wall marks everything up to now as seen.
    unawaited(_lastVisit.markNow());
    super.dispose();
  }

  Future<void> _openSheet({String? initialUrl, String? initialNote}) =>
      showAddToWallSheet(context, initialUrl: initialUrl, initialNote: initialNote);

  void _openItem(WallItem item) => context.push('/home/wall/${item.id}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(filteredWallItemsProvider);
    final hasAnyItems = ref.watch(wallItemsProvider).asData?.value.isNotEmpty ?? false;
    final pinned = ref.watch(pinnedWallItemsProvider);
    final filter = ref.watch(wallFilterProvider);
    final nameFor = ref.watch(wallNameForProvider);
    final weekCount = ref.watch(wallSharedThisWeekProvider);
    final unseen = ref.watch(unseenWallItemIdsProvider);
    final ownName = ref.watch(ownProfileProvider).asData?.value?.displayName ?? 'You';
    final spouseName = ref.watch(wallSpouseNameProvider) ?? 'Your partner';

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'wall-fab',
        tooltip: 'Add to our Wall',
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onPressed: () => _openSheet(),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    LovSpace.xs, LovSpace.sm, LovSpace.lg, LovSpace.md),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/home'),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Our Wall', style: theme.textTheme.headlineSmall),
                          Text(
                            weekCount == 0
                                ? 'Your private space for two'
                                : '$weekCount ${weekCount == 1 ? 'thing' : 'things'} shared this week',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    WallAvatar(name: ownName, isSelf: true),
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: WallAvatar(name: spouseName, isSelf: false),
                    ),
                  ],
                ),
              ),
            ),
            if (pinned.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      LovSpace.lg, 0, LovSpace.lg, LovSpace.lg),
                  child: WallPinnedRow(items: pinned, nameFor: nameFor, onTap: _openItem),
                ),
              ),
            if (hasAnyItems)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: LovSpace.lg),
                    children: [
                      WallPill(
                        label: 'All',
                        selected: filter == null,
                        onTap: () => ref.read(wallFilterProvider.notifier).select(null),
                      ),
                      for (final c in WallCollection.values) ...[
                        const SizedBox(width: LovSpace.sm),
                        WallPill(
                          label: c.label,
                          selected: filter == c,
                          onTap: () => ref.read(wallFilterProvider.notifier).select(c),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: LovSpace.md)),
            ...itemsAsync.when(
              loading: () => [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: LovSpace.lg),
                  sliver: SliverList.list(children: const [
                    _CardSkeleton(),
                    SizedBox(height: LovSpace.md),
                    _CardSkeleton(),
                  ]),
                ),
              ],
              error: (_, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Message(
                    icon: Icons.cloud_off_rounded,
                    title: "Couldn't load the Wall",
                    actionLabel: 'Try again',
                    actionIcon: Icons.refresh_rounded,
                    onAction: () => ref.invalidate(wallItemsProvider),
                  ),
                ),
              ],
              data: (items) => items.isEmpty
                  ? [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: filter == null
                            ? _Message(
                                icon: Icons.auto_awesome_rounded,
                                title: 'Share your first find',
                                body:
                                    'Reels, videos, recipes, places, little notes — keep them here, just for the two of you.',
                                actionLabel: 'Add to our Wall',
                                actionIcon: Icons.add_rounded,
                                onAction: () => _openSheet(),
                              )
                            : _Message(
                                icon: Icons.filter_list_off_rounded,
                                title: 'Nothing in ${filter.label} yet',
                              ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                            LovSpace.lg, 0, LovSpace.lg, 96),
                        sliver: SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: LovSpace.md),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            // Keyed by id so an item arriving live at the top
                            // gets a fresh entrance animation.
                            return LovEnter(
                              key: ValueKey(item.id),
                              delay: Duration(milliseconds: i < 6 ? 60 * i : 0),
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
      ),
    );
  }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WallItemCard(
      item: item,
      sharerName: sharerName,
      reactions: ref.watch(wallReactionSummaryProvider(item.id)),
      commentCount: ref.watch(wallItemCommentsProvider(item.id)).length,
      isUnseen: isUnseen,
      onOpen: onOpen,
      onOpenLink: item.url == null ? null : () => openWallLink(context, item.url!),
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
        LovShimmerBox(height: 168, radius: LovRadius.lg),
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
    this.actionIcon,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(LovSpace.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.secondary),
            child: Icon(icon, size: 36, color: scheme.primary),
          ),
          const SizedBox(height: LovSpace.lg),
          Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: LovSpace.sm),
            Text(body!, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: LovSpace.xl),
            LovButton(label: actionLabel!, onPressed: onAction, icon: actionIcon),
          ],
        ],
      ),
    );
  }
}
