import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/location/data/location_repository.dart';
import 'package:lovinity/features/location/data/location_service.dart';
import 'package:lovinity/features/location/domain/location_providers.dart';

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _FakeService implements LocationService {
  _FakeService({this.result, this.error});
  final CapturedLocation? result;
  final Object? error;
  @override
  Future<CapturedLocation> capture() async {
    if (error != null) throw error!;
    return result!;
  }
}

class _FakeRepo implements LocationRepository {
  Map<String, dynamic>? captured;
  @override
  Future<void> updateLocation({
    required String userId,
    required double latitude,
    required double longitude,
    required String timezone,
  }) async {
    captured = {
      'userId': userId,
      'lat': latitude,
      'long': longitude,
      'tz': timezone,
    };
  }
}

ProviderContainer _containerWith({
  required LocationService service,
  required _FakeRepo repo,
}) {
  final session = _MockSession();
  final user = _MockUser();
  when(() => user.id).thenReturn('user-1');
  when(() => session.user).thenReturn(user);

  return ProviderContainer(overrides: [
    authSessionProvider.overrideWith((ref) => Stream.value(session)),
    locationServiceProvider.overrideWithValue(service),
    locationRepositoryProvider.overrideWithValue(repo),
  ]);
}

void main() {
  test('captureAndSave persists captured location and ends in data state',
      () async {
    final repo = _FakeRepo();
    final container = _containerWith(
      service: _FakeService(
        result: const CapturedLocation(
          latitude: 40.7128,
          longitude: -74.006,
          timezone: 'America/New_York',
        ),
      ),
      repo: repo,
    );
    addTearDown(container.dispose);
    container.listen(authSessionProvider, (_, _) {});
    await container.read(authSessionProvider.future);

    await container.read(locationControllerProvider.notifier).captureAndSave();

    expect(repo.captured, {
      'userId': 'user-1',
      'lat': 40.7128,
      'long': -74.006,
      'tz': 'America/New_York',
    });
    expect(container.read(locationControllerProvider).hasError, isFalse);
  });

  test('captureAndSave surfaces a LocationFailure and does not save', () async {
    final repo = _FakeRepo();
    final container = _containerWith(
      service: _FakeService(
        error: const LocationFailure(LocationErrorReason.permissionDenied),
      ),
      repo: repo,
    );
    addTearDown(container.dispose);
    container.listen(authSessionProvider, (_, _) {});
    await container.read(authSessionProvider.future);

    await container.read(locationControllerProvider.notifier).captureAndSave();

    expect(repo.captured, isNull);
    final state = container.read(locationControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<LocationFailure>());
  });

  test('LocationFailure.userMessage covers every reason', () {
    for (final reason in LocationErrorReason.values) {
      expect(LocationFailure(reason).userMessage, isNotEmpty);
    }
  });
}
