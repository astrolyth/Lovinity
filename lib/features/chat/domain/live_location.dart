import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'chat_payload.dart';
import 'chat_providers.dart';

const liveLocationLength = Duration(hours: 1);
const _minGap = Duration(seconds: 30);

/// Why a live share couldn't start.
enum LiveLocationProblem { servicesOff, denied, notReady }

/// The session id of this phone's live-location share, or null when not
/// sharing. Updates go out every time you move 25 m (at most every 30 s), in
/// the background too: Android shows a foreground notification, iOS the blue
/// location indicator. It stops by itself after an hour.
final liveLocationProvider = NotifierProvider<LiveLocation, String?>(
  LiveLocation.new,
);

class LiveLocation extends Notifier<String?> {
  StreamSubscription<Position>? _sub;
  Timer? _end;
  Position? _last;
  DateTime _lastSent = DateTime(0);
  DateTime _until = DateTime(0);

  @override
  String? build() {
    ref.onDispose(_teardown);
    return null;
  }

  Future<LiveLocationProblem?> start() async {
    if (state != null) return null;
    final service = ref.read(chatServiceProvider).value;
    if (service == null) return LiveLocationProblem.notReady;
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LiveLocationProblem.servicesOff;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return LiveLocationProblem.denied;
    }

    final session = const Uuid().v4();
    state = session;
    _until = DateTime.now().add(liveLocationLength);
    _end = Timer(liveLocationLength, stop);
    final first = await Geolocator.getCurrentPosition();
    await _send(first, force: true);
    _sub = Geolocator.getPositionStream(
      locationSettings: _settings(),
    ).listen((p) => _send(p), onError: (_) {});
    return null;
  }

  Future<void> stop() async {
    final last = _last, session = state;
    _teardown();
    state = null;
    if (last != null && session != null) {
      await ref
          .read(chatServiceProvider)
          .value
          ?.sendLocation(_payload(session, last, ended: true));
    }
  }

  Future<void> _send(Position p, {bool force = false}) async {
    final session = state;
    if (session == null) return;
    _last = p;
    final now = DateTime.now();
    if (!force && now.difference(_lastSent) < _minGap) return;
    _lastSent = now;
    await ref.read(chatServiceProvider).value?.sendLocation(_payload(session, p));
  }

  LocationPayload _payload(String session, Position p, {bool ended = false}) =>
      LocationPayload(
        session: session,
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
        until: ended ? DateTime.now() : _until,
        ended: ended,
      );

  void _teardown() {
    _end?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
  }
}

LocationSettings _settings() => Platform.isAndroid
    ? AndroidSettings(
        distanceFilter: 25,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Sharing your live location',
          notificationText: 'Your spouse can see where you are for an hour.',
        ),
      )
    : AppleSettings(
        distanceFilter: 25,
        activityType: ActivityType.other,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
