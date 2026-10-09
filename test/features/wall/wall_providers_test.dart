import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';

WallItem _item(String id, {String by = 'sp', bool pinned = false,
        WallCollection? collection, DateTime? at}) =>
    WallItem(
      id: id,
      coupleId: 'c',
      addedBy: by,
      source: WallSource.note,
      note: 'n $id',
      collection: collection,
      isPinned: pinned,
      createdAt: at ?? DateTime.now(),
    );

ProviderContainer _container({
  List<WallItem> items = const [],
  List<WallReaction> reactions = const [],
  SecureStore? store,
}) {
  final c = ProviderContainer(overrides: [
    wallSelfIdProvider.overrideWithValue('me'),
    wallItemsProvider.overrideWith((ref) => Stream.value(items)),
    wallReactionsProvider.overrideWith((ref) => Stream.value(reactions)),
    wallCommentsProvider.overrideWith((ref) => Stream.value(const <WallComment>[])),
    spouseProfileProvider.overrideWith((ref) async => null),
    secureStoreProvider.overrideWithValue(store ?? InMemorySecureStore()),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  c.listen(wallItemsProvider, (_, _) {});
  c.listen(wallReactionsProvider, (_, _) {});
  await c.read(wallItemsProvider.future);
  await c.read(wallReactionsProvider.future);
}

void main() {
  test('filter narrows items by collection; null shows all', () async {
    final c = _container(items: [
      _item('a', collection: WallCollection.recipes),
      _item('b', collection: WallCollection.places),
      _item('c'),
    ]);
    await _settle(c);
    expect(c.read(filteredWallItemsProvider).value!.map((i) => i.id), ['a', 'b', 'c']);
    c.read(wallFilterProvider.notifier).select(WallCollection.recipes);
    expect(c.read(filteredWallItemsProvider).value!.map((i) => i.id), ['a']);
    c.read(wallFilterProvider.notifier).select(null);
    expect(c.read(filteredWallItemsProvider).value!, hasLength(3));
  });

  test('pinned items and single-item lookup', () async {
    final c = _container(items: [_item('a', pinned: true), _item('b')]);
    await _settle(c);
    expect(c.read(pinnedWallItemsProvider).map((i) => i.id), ['a']);
    expect(c.read(wallItemProvider('b')).value!.id, 'b');
    expect(c.read(wallItemProvider('missing')).value, isNull);
  });

  test('reaction summary is per item and marks mine', () async {
    final c = _container(items: [_item('a')], reactions: const [
      WallReaction(itemId: 'a', userId: 'me', kind: WallReactionKind.dua),
      WallReaction(itemId: 'a', userId: 'sp', kind: WallReactionKind.dua),
    ]);
    await _settle(c);
    expect(c.read(wallReactionSummaryProvider('a')), const [
      ReactionCount(kind: WallReactionKind.dua, count: 2, mine: true),
    ]);
  });

  test('nameFor: You, else the partner fallback', () async {
    final c = _container();
    final nameFor = c.read(wallNameForProvider);
    expect(nameFor('me'), 'You');
    expect(nameFor('sp'), 'Your partner');
  });

  test('last visit persists per account and drives unseen ids', () async {
    final store = InMemorySecureStore();
    final c = _container(store: store, items: [
      _item('old', at: DateTime.now().subtract(const Duration(days: 2))),
      _item('mine', by: 'me'),
    ]);
    await _settle(c);
    c.listen(wallLastVisitProvider, (_, _) {});
    await c.read(wallLastVisitProvider.future);
    expect(c.read(unseenWallItemIdsProvider), {'old'}, reason: 'never visited');

    await c.read(wallLastVisitProvider.notifier).markNow();
    expect(c.read(unseenWallItemIdsProvider), isEmpty);
    expect(await store.read('wall.last_visit.me'), isNotNull);
  });
}
