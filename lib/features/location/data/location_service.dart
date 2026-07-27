import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';

/// Why a location capture failed, so the UI can show a helpful message.
enum LocationErrorReason {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationFailure implements Exception {
  const LocationFailure(this.reason, [this.message]);
  final LocationErrorReason reason;
  final String? message;

  String get userMessage => switch (reason) {
        LocationErrorReason.serviceDisabled =>
          'Location services are turned off. Turn them on and try again.',
        LocationErrorReason.permissionDenied =>
          'Location permission was denied. Please allow it to set your prayer times.',
        LocationErrorReason.permissionDeniedForever =>
          'Location is blocked for this app. Enable it in Settings to continue.',
        LocationErrorReason.unavailable =>
          'Could not read your location. Please try again.',
      };
}

/// Coordinates + IANA timezone for a captured location.
class CapturedLocation {
  const CapturedLocation({
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });
  final double latitude;
  final double longitude;
  final String timezone;
}

/// Abstracts the device location + timezone lookup so the controller can be
/// unit-tested with a fake, while the real impl wraps geolocator/flutter_timezone.
abstract class LocationService {
  Future<CapturedLocation> capture();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<CapturedLocation> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(LocationErrorReason.serviceDisabled);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(LocationErrorReason.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(LocationErrorReason.permissionDeniedForever);
    }

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (e) {
      throw LocationFailure(LocationErrorReason.unavailable, e.toString());
    }

    final tz = await FlutterTimezone.getLocalTimezone();
    return CapturedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      timezone: tz.identifier,
    );
  }
}
