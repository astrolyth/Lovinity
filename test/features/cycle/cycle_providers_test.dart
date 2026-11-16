import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lovinity/shared/models/cycle_record.dart';
import 'package:lovinity/shared/models/user_profile.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/cycle/domain/cycle_providers.dart';

void main() {
  test('activeCycleProvider picks the record active today', () async {
    final today = DateTime.now();
    final active = CycleRecord(
      id: 'a',
      userId: 'u',
      coupleId: 'c',
      startedOn: today.subtract(const Duration(days: 2)),
      endedOn: null,
      visibility: 'private',
    );
    final container = ProviderContainer(overrides: [
      ownCycleHistoryProvider.overrideWith((ref) => Stream.value([active])),
    ]);
    addTearDown(container.dispose);

    // Keep `ownCycleHistoryProvider` alive across the awaited read: with
    // flutter_riverpod ^3.3 an unlistened StreamProvider auto-disposes once
    // its `.future` resolves, which would reset it to a loading state (and
    // `activeCycleProvider`'s `.asData` to null) by the time we read it
    // below. A `listen` keeps it retained for the container's lifetime.
    container.listen(ownCycleHistoryProvider, (_, _) {}, fireImmediately: true);
    await container.read(ownCycleHistoryProvider.future);

    expect(container.read(activeCycleProvider)?.id, 'a');
  });

  test('activeCycleProvider returns null when no record covers today',
      () async {
    final today = DateTime.now();
    final past = CycleRecord(
      id: 'b',
      userId: 'u',
      coupleId: 'c',
      startedOn: today.subtract(const Duration(days: 40)),
      endedOn: today.subtract(const Duration(days: 35)),
      visibility: 'private',
    );
    final container = ProviderContainer(overrides: [
      ownCycleHistoryProvider.overrideWith((ref) => Stream.value([past])),
    ]);
    addTearDown(container.dispose);

    container.listen(ownCycleHistoryProvider, (_, _) {}, fireImmediately: true);
    await container.read(ownCycleHistoryProvider.future);

    expect(container.read(activeCycleProvider), isNull);
  });

  test('isWifeProvider is true when own profile gender is female', () async {
    final container = ProviderContainer(overrides: [
      ownProfileProvider.overrideWith((ref) async => const UserProfile(
            id: 'u',
            displayName: 'Amina',
            timezone: 'UTC',
            madhhab: 'shafi',
            calcMethod: 'muslim_world_league',
            gender: 'female',
          )),
    ]);
    addTearDown(container.dispose);

    await container.read(ownProfileProvider.future);

    expect(container.read(isWifeProvider), isTrue);
  });

  test('isWifeProvider is false when own profile gender is male', () async {
    final container = ProviderContainer(overrides: [
      ownProfileProvider.overrideWith((ref) async => const UserProfile(
            id: 'u',
            displayName: 'Yusuf',
            timezone: 'UTC',
            madhhab: 'shafi',
            calcMethod: 'muslim_world_league',
            gender: 'male',
          )),
    ]);
    addTearDown(container.dispose);

    await container.read(ownProfileProvider.future);

    expect(container.read(isWifeProvider), isFalse);
  });

  group('filterPartnerShared', () {
    test('keeps only the partner\'s shared rows, newest first', () {
      final today = DateTime.now();
      final selfPrivate = CycleRecord(
        id: 'self-private', userId: 'self', coupleId: 'c',
        startedOn: today.subtract(const Duration(days: 5)),
        endedOn: null, visibility: 'private');
      final selfShared = CycleRecord(
        id: 'self-shared', userId: 'self', coupleId: 'c',
        startedOn: today.subtract(const Duration(days: 4)),
        endedOn: null, visibility: 'shared');
      final partnerPrivate = CycleRecord(
        id: 'partner-private', userId: 'partner', coupleId: 'c',
        startedOn: today.subtract(const Duration(days: 60)),
        endedOn: today.subtract(const Duration(days: 55)),
        visibility: 'private');
      final partnerSharedOld = CycleRecord(
        id: 'partner-shared-old', userId: 'partner', coupleId: 'c',
        startedOn: today.subtract(const Duration(days: 30)),
        endedOn: today.subtract(const Duration(days: 26)),
        visibility: 'shared');
      final partnerSharedNew = CycleRecord(
        id: 'partner-shared-new', userId: 'partner', coupleId: 'c',
        startedOn: today.subtract(const Duration(days: 1)),
        endedOn: null, visibility: 'shared');

      final result = filterPartnerShared(
        [selfPrivate, selfShared, partnerPrivate, partnerSharedOld, partnerSharedNew],
        selfId: 'self',
      );

      expect(result.map((r) => r.id).toList(),
          ['partner-shared-new', 'partner-shared-old']);
    });

    test('returns an empty list when the partner has no shared rows', () {
      final partnerPrivate = CycleRecord(
        id: 'partner-private', userId: 'partner', coupleId: 'c',
        startedOn: DateTime.now(), endedOn: null, visibility: 'private');

      expect(filterPartnerShared([partnerPrivate], selfId: 'self'), isEmpty);
    });
  });

  test('partnerActiveCycleProvider picks the partner\'s record active today',
      () async {
    final today = DateTime.now();
    final active = CycleRecord(
      id: 'p', userId: 'partner', coupleId: 'c',
      startedOn: today.subtract(const Duration(days: 1)),
      endedOn: null, visibility: 'shared');
    final container = ProviderContainer(overrides: [
      partnerSharedCycleProvider.overrideWith((ref) => Stream.value([active])),
    ]);
    addTearDown(container.dispose);

    container.listen(partnerSharedCycleProvider, (_, _) {}, fireImmediately: true);
    await container.read(partnerSharedCycleProvider.future);

    expect(container.read(partnerActiveCycleProvider)?.id, 'p');
  });

  test('partnerActiveCycleProvider returns null with no active partner record',
      () async {
    final container = ProviderContainer(overrides: [
      partnerSharedCycleProvider.overrideWith((ref) => Stream.value(const [])),
    ]);
    addTearDown(container.dispose);

    container.listen(partnerSharedCycleProvider, (_, _) {}, fireImmediately: true);
    await container.read(partnerSharedCycleProvider.future);

    expect(container.read(partnerActiveCycleProvider), isNull);
  });
}
