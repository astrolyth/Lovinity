import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/features/wall/data/wall_repository.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';
import 'package:lovinity/shared/models/couple.dart';

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

/// Records which couples were opened; serves fixed items.
class _FakeRepo extends Fake implements WallRepository {
  _FakeRepo({this.items = const []});

  final List<WallItem> items;
  final itemCalls = <String>[];

  @override
  Stream<List<WallItem>> watchItems(String coupleId) {
    itemCalls.add(coupleId);
    return Stream.value(items);
  }

  @override
  Stream<List<WallReaction>> watchReactions(String coupleId) =>
      Stream.value(const <WallReaction>[]);

  @override
  Stream<List<WallComment>> watchComments(String coupleId) =>
      Stream.value(const <WallComment>[]);
}

/// Container that lets the real couple-gating in wall_providers run.
ProviderContainer _coupleContainer({
  required Stream<Couple?> couple,
  required _FakeRepo repo,
}) {
  final c = ProviderContainer(overrides: [
    wallSelfIdProvider.overrideWithValue('me'),
    currentCoupleProvider.overrideWith((ref) => couple),
    wallRepositoryProvider.overrideWithValue(repo),
    spouseProfileProvider.overrideWith((ref) async => null),
    secureStoreProvider.overrideWithValue(InMemorySecureStore()),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Container for one account on a device whose secure store may be shared.
ProviderContainer _accountContainer(String userId, SecureStore store) {
  final c = ProviderContainer(overrides: [
    wallSelfIdProvider.overrideWithValue(userId),
    secureStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(c.dispose);
  return c;
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

  test('the filter resets once nothing watches the Wall list any more', () async {
    final c = _container(items: [_item('a', collection: WallCollection.recipes)]);
    await _settle(c);
    final sub = c.listen(filteredWallItemsProvider, (_, _) {});
    c.read(wallFilterProvider.notifier).select(WallCollection.recipes);
    expect(c.read(wallFilterProvider), WallCollection.recipes);

    sub.close(); // the Wall screen went away
    await Future<void>.delayed(Duration.zero);
    expect(c.exists(wallFilterProvider), isFalse);
    expect(c.read(wallFilterProvider), isNull);
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

  test('items stay loading while the couple is still loading', () async {
    final couple = StreamController<Couple?>();
    addTearDown(couple.close);
    final repo = _FakeRepo();
    final c = _coupleContainer(couple: couple.stream, repo: repo);
    c.listen(wallItemsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(c.read(wallItemsProvider).isLoading, isTrue);
    expect(repo.itemCalls, isEmpty, reason: 'no feed opened before the couple resolves');
  });

  test('items are empty, not loading, when there is no couple', () async {
    final repo = _FakeRepo();
    final c = _coupleContainer(couple: Stream<Couple?>.value(null), repo: repo);
    c.listen(wallItemsProvider, (_, _) {});
    expect(await c.read(wallItemsProvider.future), isEmpty);
    expect(repo.itemCalls, isEmpty);
  });

  test('items error, not empty, when the couple fails to load', () async {
    final repo = _FakeRepo();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        wallSelfIdProvider.overrideWithValue('me'),
        currentCoupleProvider
            .overrideWith((ref) => Stream<Couple?>.error(Exception('offline'))),
        wallRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    c.listen(wallItemsProvider, (_, _) {});
    await expectLater(c.read(wallItemsProvider.future), throwsA(isA<Exception>()));
    expect(c.read(wallItemsProvider).hasError, isTrue);
    expect(repo.itemCalls, isEmpty);
  });

  test('keeps the last couple feed when the couple stream errors later', () async {
    final couple = StreamController<Couple?>();
    addTearDown(couple.close);
    final repo = _FakeRepo(items: [_item('p')]);
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        wallSelfIdProvider.overrideWithValue('me'),
        currentCoupleProvider.overrideWith((ref) => couple.stream),
        wallRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(c.dispose);
    c.listen(wallItemsProvider, (_, _) {});
    couple.add(const Couple(
        id: 'c1', memberA: 'me', memberB: 'sp', status: 'active', longDistance: false));
    expect((await c.read(wallItemsProvider.future)).map((i) => i.id), ['p']);

    couple.addError(Exception('blip'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(currentCoupleProvider).hasError, isTrue);
    // The feed reopens for the last known couple instead of going empty.
    expect((await c.read(wallItemsProvider.future)).map((i) => i.id), ['p']);
    expect(repo.itemCalls, ['c1', 'c1']);
  });

  test('opens the couple feed once paired', () async {
    final repo = _FakeRepo(items: [_item('p')]);
    final couple = Stream<Couple?>.value(const Couple(
      id: 'c1',
      memberA: 'me',
      memberB: 'sp',
      status: 'active',
      longDistance: false,
    ));
    final c = _coupleContainer(couple: couple, repo: repo);
    c.listen(wallItemsProvider, (_, _) {});
    expect((await c.read(wallItemsProvider.future)).map((i) => i.id), ['p']);
    expect(repo.itemCalls, ['c1']);
  });

  test('disposing the container closes the preview service client', () async {
    // A closed http.Client throws; fetch() swallows that and returns null.
    // The URL is under .invalid so no real request can succeed either way.
    final c = ProviderContainer();
    final service = c.read(linkPreviewServiceProvider);
    c.dispose();
    expect(await service.fetch('https://lovinity-test.invalid/'), isNull);
  });

  test('last visit is per account on a shared device', () async {
    final store = InMemorySecureStore();
    final mine = _accountContainer('me', store);
    final theirs = _accountContainer('other', store);
    mine.listen(wallLastVisitProvider, (_, _) {});
    await mine.read(wallLastVisitProvider.future);
    await mine.read(wallLastVisitProvider.notifier).markNow();

    expect(await store.read('wall.last_visit.me'), isNotNull);
    expect(await store.read('wall.last_visit.other'), isNull);
    theirs.listen(wallLastVisitProvider, (_, _) {});
    expect(await theirs.read(wallLastVisitProvider.future), isNull);
  });
}
