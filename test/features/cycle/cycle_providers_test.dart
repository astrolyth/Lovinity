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
}
