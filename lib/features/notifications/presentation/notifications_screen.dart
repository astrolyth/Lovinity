// lib/features/notifications/presentation/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_store.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the screen marks everything currently unread as read.
    ref.read(notificationStoreProvider).markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationsAsync = ref.watch(notificationsListProvider);

    return LovScaffold(
      title: 'Notifications',
      padded: false,
      child: notificationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load notifications',
              style: theme.textTheme.bodyMedium),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(LovSpace.xl),
                child: Text(
                  'No notifications yet',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: LovSpace.md),
            itemCount: items.length,
            itemBuilder: (context, index) => _NotificationTile(item: items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});
  final NotificationRow item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = item.readAt == null;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: LovSpace.lg, vertical: LovSpace.xs),
      child: LovCard(
        variant: LovCardVariant.tonal,
        onTap: () => context.go(item.route),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (unread)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: LovSpace.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.body!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
