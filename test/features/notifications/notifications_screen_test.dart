import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/notification_providers.dart';
import 'package:lovinity/core/notifications/notification_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';
import 'package:lovinity/features/notifications/presentation/notifications_screen.dart';

void main() {
  testWidgets('renders notifications and marks them read on open', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = NotificationStore(db);
    await store.insert(
      kind: 'pairing',
      title: "You're connected",
      body: 'You and your partner are now paired 💛',
      route: '/home',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationStoreProvider.overrideWithValue(store),
        notificationsListProvider.overrideWith((ref) => store.watchAll()),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ));
    await tester.pump();

    expect(find.text("You're connected"), findsOneWidget);
    expect(find.text('You and your partner are now paired 💛'), findsOneWidget);

    // Opening the screen marks it read. Verified via a one-shot get(), not
    // a second .watch() stream -- two concurrent reactive Drift streams
    // against the same in-memory db (this one, plus the widget's own
    // notificationsListProvider) hang on disposal in this environment. See
    // task-11-report.md for the full diagnosis.
    await tester.pump();
    final rows = await db.select(db.appNotifications).get();
    expect(rows.single.readAt, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('shows an empty state with no notifications', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = NotificationStore(db);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationStoreProvider.overrideWithValue(store),
        notificationsListProvider.overrideWith((ref) => store.watchAll()),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    ));
    await tester.pump();

    expect(find.text('No notifications yet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
