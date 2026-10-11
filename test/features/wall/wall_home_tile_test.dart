import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';
import 'package:lovinity/features/wall/presentation/wall_home_tile.dart';

Future<void> _pump(WidgetTester tester, List<WallItem> items) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wallItemsProvider.overrideWith((ref) => Stream.value(items)),
      wallSelfIdProvider.overrideWithValue('me'),
      spouseProfileProvider.overrideWith((ref) async => null),
      secureStoreProvider.overrideWithValue(InMemorySecureStore()),
    ],
    child: MaterialApp(
      theme: LovTheme.dark(),
      home: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: WallHomeTile())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty Wall invites the first share', (tester) async {
    await _pump(tester, const []);
    expect(find.text('Our Wall'), findsOneWidget);
    expect(find.text('Share your first find together.'), findsOneWidget);
    expect(find.byKey(const Key('wall-unseen-dot')), findsNothing);
  });

  testWidgets('shows the latest item and an unseen dot for spouse posts', (tester) async {
    await _pump(tester, [
      WallItem(
        id: 'i1', coupleId: 'c', addedBy: 'sp', url: 'https://youtu.be/a',
        title: 'Morning habit', source: WallSource.youtube, isPinned: false,
        createdAt: DateTime.now(),
      ),
    ]);
    expect(find.text('Your partner · Morning habit'), findsOneWidget);
    expect(find.byKey(const Key('wall-unseen-dot')), findsOneWidget);
  });
}
