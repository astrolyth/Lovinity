import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../data/location_repository.dart';
import '../data/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return LocationRepository(ref.read(supabaseClientProvider));
});

/// Drives the "Set your location" flow: capture device location + timezone,
/// persist it, and refresh the profile so prayer times recompute.
///
/// Exposes an `AsyncValue<void>` so the UI can show progress and surface a
/// [LocationFailure] message. Throws are captured into the state (never leak).
class LocationController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> captureAndSave() async {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final loc = await ref.read(locationServiceProvider).capture();
      await ref.read(locationRepositoryProvider).updateLocation(
            userId: session.user.id,
            latitude: loc.latitude,
            longitude: loc.longitude,
            timezone: loc.timezone,
          );
      ref.invalidate(ownProfileProvider);
    });
  }
}

final locationControllerProvider =
    AsyncNotifierProvider<LocationController, void>(LocationController.new);
