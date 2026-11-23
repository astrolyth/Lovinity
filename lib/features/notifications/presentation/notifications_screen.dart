// lib/features/notifications/presentation/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/notifications/notification_store.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// What was unread when the screen opened: it keeps its dot for this
  /// visit even though opening marks everything read.
  Set<String>? _fresh;

  @override
  void initState() {
    super.initState();
    // Opening the screen marks everything currently unread as read. Caught
    // so a failed write (e.g. the local db closing mid-flight during an
    // account switch) can't surface as an unhandled async error.
    ref.read(notificationStoreProvider).markAllRead().catchError((Object e) {
      debugPrint('NotificationsScreen: failed to mark all read: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final async = ref.watch(notificationsListProvider);
    final items = async.asData?.value;
    if (items != null) {
      _fresh ??= {
        for (final n in items)
          if (n.readAt == null) n.id,
      };
    }
    final now = DateTime.now();
    bool isToday(DateTime t) =>
        t.year == now.year && t.month == now.month && t.day == now.day;
    final today = [...?items?.where((n) => isToday(n.createdAt.toLocal()))];
    final earlier = [...?items?.where((n) => !isToday(n.createdAt.toLocal()))];
    final newCount = _fresh?.length ?? 0;

    return LovPage(
      title: 'Notifications',
      action: LovIconButton(
        icon: Icons.tune_rounded,
        label: 'Notification settings',
        onTap: () => context.push('/home/settings'),
      ),
      slivers: [
        ...async.when(
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (_, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Could not load notifications',
                  style: TextStyle(color: p.muted),
                ),
              ),
            ),
          ],
          data: (all) => all.isEmpty
              ? [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const LovGlyph(
                            icon: Icons.notifications_none_rounded,
                            size: 72,
                            radius: 24,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All quiet for now',
                            style: lovDisplay(context, size: 21),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Prayers, letters and moments from your spouse '
                            'show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]
              : [
                  if (today.isNotEmpty) ...[
                    _label('Today${newCount > 0 ? ' · $newCount new' : ''}'),
                    _list(today, 0),
                  ],
                  if (earlier.isNotEmpty) ...[
                    _label(
                      today.isEmpty && newCount > 0
                          ? 'Earlier · $newCount new'
                          : 'Earlier',
                    ),
                    _list(earlier, 1),
                  ],
                ],
        ),
      ],
    );
  }

  Widget _label(String t) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: LovEyebrow(t),
    ),
  );

  Widget _list(List<NotificationRow> rows, int i) => SliverToBoxAdapter(
    child: LovRise(
      delay: Duration(milliseconds: 100 * i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LovSurface(
          radius: 20,
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              for (final (j, n) in rows.indexed) ...[
                if (j > 0) Divider(height: 1, color: context.lov.surface2),
                _NotificationTile(
                  item: n,
                  fresh: _fresh?.contains(n.id) ?? false,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Glyph per notification kind; spouse activity is rose, your own is gold.
(IconData, bool) _glyphFor(String kind) => switch (kind) {
  'prayer' => (Icons.dark_mode_outlined, false),
  'chat' || 'message' => (Icons.chat_bubble_outline_rounded, true),
  'moment' || 'moment_nudge' => (Icons.photo_camera_outlined, true),
  'wall' => (Icons.push_pin_outlined, true),
  'letter' => (Icons.mail_outline_rounded, true),
  'cycle' => (Icons.water_drop_outlined, true),
  'dua' || 'tasbih' => (Icons.menu_book_outlined, false),
  'question' => (Icons.forum_outlined, true),
  'gratitude' => (Icons.wb_sunny_outlined, true),
  'calendar' || 'grocery' => (Icons.calendar_today_outlined, false),
  'pairing' => (Icons.favorite_border_rounded, true),
  _ => (Icons.notifications_none_rounded, false),
};

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.fresh});
  final NotificationRow item;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final (icon, fromSpouse) = _glyphFor(item.kind);
    final t = item.createdAt.toLocal();
    final ago = DateTime.now().difference(t);
    final time = ago.inMinutes < 1
        ? 'Just now'
        : ago.inHours < 1
        ? '${ago.inMinutes} min ago'
        : ago.inDays < 1
        ? DateFormat.jm().format(t)
        : DateFormat('EEE d MMM').format(t);
    final body = item.body?.trim();
    return Semantics(
      button: true,
      label: [item.title, ?body, time, if (fresh) 'new'].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.go(item.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fromSpouse ? p.partnerSoft : p.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: fromSpouse ? p.partner : p.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: fresh ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (body != null && body.isNotEmpty)
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: p.text2,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(time, style: TextStyle(fontSize: 12, color: p.muted)),
                  ],
                ),
              ),
              if (fresh)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 10, top: 6),
                  decoration: BoxDecoration(
                    color: p.partner,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
