import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/lov_scaffold.dart';
import '../../wall/domain/wall_providers.dart';
import '../domain/moment.dart';
import '../domain/moments_providers.dart';

/// The Moments tab: story rings up top, a day-by-day grid below, and a big
/// camera button. Media can only come from the live camera.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments = ref.watch(momentsProvider);
    final self = ref.watch(wallSelfIdProvider) ?? '';
    final spouse = ref.watch(wallSpouseNameProvider) ?? 'Partner';

    return LovScaffold(
      title: 'Moments',
      subtitle: const Text('Live updates for each other — camera only'),
      floatingActionButton: FloatingActionButton.large(
        heroTag: 'moment-camera',
        tooltip: 'Capture a moment',
        onPressed: () => context.push('/moments/camera'),
        child: const Icon(Icons.camera_alt_rounded),
      ),
      child: moments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(momentsProvider),
            child: const Text("Couldn't load moments — tap to retry"),
          ),
        ),
        data: (list) {
          final partnerStart = partnerStoryStart(list, self);
          final mine = list.where((m) => m.senderId == self).firstOrNull;
          final unseen = list
              .where((m) => m.senderId != self && m.viewedAt == null)
              .length;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: LovSpace.md),
                  child: Row(
                    children: [
                      _StoryRing(
                        label: spouse,
                        moment: partnerStart,
                        highlighted: unseen > 0,
                        badge: unseen > 0 ? '$unseen new' : null,
                        onTap: partnerStart == null
                            ? null
                            : () => context.push('/moments/${partnerStart.id}'),
                      ),
                      const SizedBox(width: LovSpace.lg),
                      _StoryRing(
                        label: 'You',
                        moment: mine,
                        highlighted: false,
                        onTap: () => context.push(
                          mine == null
                              ? '/moments/camera'
                              : '/moments/${mine.id}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (list.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: _Empty())
              else
                for (final (day, items) in groupByDay(list)) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: LovSpace.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _dayLabel(day),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push(
                              '/moments/vlog/${DateFormat('yyyy-MM-dd').format(day)}',
                            ),
                            icon: const Icon(Icons.play_circle_outline_rounded),
                            label: const Text('Play vlog'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: LovSpace.xs,
                          crossAxisSpacing: LovSpace.xs,
                          childAspectRatio: 3 / 4,
                        ),
                    itemCount: items.length,
                    itemBuilder: (_, i) =>
                        _Tile(moment: items[i], selfId: self),
                  ),
                ],
              // Room for the FAB.
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          );
        },
      ),
    );
  }
}

String _dayLabel(DateTime day) {
  final today = vlogDay(DateTime.now());
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat.MMMEd().format(day);
}

class _StoryRing extends StatelessWidget {
  const _StoryRing({
    required this.label,
    required this.moment,
    required this.highlighted,
    required this.onTap,
    this.badge,
  });
  final String label;
  final Moment? moment;
  final bool highlighted;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ringColor = highlighted
        ? theme.colorScheme.primary
        : theme.dividerColor;
    final preview = moment?.previewPath;
    return Semantics(
      button: onTap != null,
      label: '$label moments${badge == null ? '' : ', $badge'}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 3),
              ),
              child: ClipOval(
                child: preview == null
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          moment == null
                              ? Icons.add_a_photo_outlined
                              : Icons.play_arrow_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : _SignedImage(path: preview),
              ),
            ),
            const SizedBox(height: LovSpace.xs),
            Text(badge ?? label, style: theme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.moment, required this.selfId});
  final Moment moment;
  final String selfId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unseen = moment.senderId != selfId && moment.viewedAt == null;
    final time = DateFormat.jm().format(moment.createdAt);
    final preview = moment.previewPath;
    return Semantics(
      button: true,
      label:
          '${moment.isVideo ? 'Video' : 'Photo'} at $time${unseen ? ', new' : ''}',
      child: GestureDetector(
        onTap: () => context.push('/moments/${moment.id}'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LovRadius.sm),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview != null)
                _SignedImage(path: preview)
              else
                ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              // Snapchat-style: unopened moments stay veiled until viewed.
              if (unseen) const ColoredBox(color: Colors.black54),
              Positioned(
                left: 6,
                bottom: 6,
                child: Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
              ),
              if (moment.isVideo)
                const Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 18,
                    shadows: [Shadow(blurRadius: 6)],
                  ),
                ),
              if (unseen)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LovSpace.sm,
                      vertical: LovSpace.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(LovRadius.pill),
                    ),
                    child: Text(
                      'Tap to view',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedImage extends ConsumerWidget {
  const _SignedImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return ref
        .watch(momentSignedUrlProvider(path))
        .when(
          data: (u) => Image.network(
            u,
            fit: BoxFit.cover,
            cacheWidth: 360,
            errorBuilder: (_, _, _) => placeholder,
          ),
          loading: () => placeholder,
          error: (_, _) => placeholder,
        );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.camera_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: LovSpace.md),
          Text('No moments yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: LovSpace.xs),
          Text(
            "Show your partner what you're up to right now.",
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
