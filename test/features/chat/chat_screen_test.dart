import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/features/chat/data/chat_store.dart';
import 'package:lovinity/features/chat/domain/chat_providers.dart';
import 'package:lovinity/features/chat/presentation/chat_screen.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  testWidgets('renders messages from the store', (tester) async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final store = ChatStore(db);
    await store.upsertMessage(id: 'm1', senderId: 'a', body: 'salam alaykum',
        createdAt: DateTime(2026), status: 'delivered');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversationMessagesProvider.overrideWith((ref) => store.watchConversation()),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ));
    await tester.pump();
    expect(find.text('salam alaykum'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // composer

    // Unmount explicitly (inside the fake-async zone) and elapse past drift's
    // zero-duration stream-close timer, so the framework's automatic
    // post-test unmount doesn't trip over a still-pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
