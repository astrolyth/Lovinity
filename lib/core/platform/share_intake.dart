import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Text another app shared into Lovinity via the OS Share menu.
@immutable
class SharedPayload {
  const SharedPayload({required this.text, this.subject});

  final String text;
  final String? subject;

  static SharedPayload? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final subject = raw['subject'];
    return SharedPayload(
      text: text,
      subject: subject is String && subject.trim().isNotEmpty ? subject : null,
    );
  }
}

/// Bridge to MainActivity.kt (Android) / SceneDelegate.swift (iOS). Cold-start shares are pulled
/// with [takeInitialShare]; shares while running arrive on [shares].
class ShareIntake {
  ShareIntake({MethodChannel? channel, bool? enabled})
      : _channel = channel ?? const MethodChannel(channelName),
        _enabled = enabled ?? (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)) {
    if (_enabled) _channel.setMethodCallHandler(_handle);
  }

  static const channelName = 'lovinity/share';

  final MethodChannel _channel;
  final bool _enabled;
  final _controller = StreamController<SharedPayload>.broadcast();

  Stream<SharedPayload> get shares => _controller.stream;

  Future<SharedPayload?> takeInitialShare() async {
    if (!_enabled) return null;
    try {
      return SharedPayload.fromChannel(
          await _channel.invokeMethod<Object?>('getInitialShare'));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'onShare') {
      final payload = SharedPayload.fromChannel(call.arguments);
      if (payload != null && !_controller.isClosed) _controller.add(payload);
    }
    return null;
  }

  void dispose() {
    if (_enabled) _channel.setMethodCallHandler(null);
    _controller.close();
  }
}

final shareIntakeProvider = Provider<ShareIntake>((ref) {
  final intake = ShareIntake();
  ref.onDispose(intake.dispose);
  return intake;
});

/// A share waiting for the Wall screen to open its add sheet.
class PendingShare extends Notifier<SharedPayload?> {
  @override
  SharedPayload? build() => null;

  void set(SharedPayload payload) => state = payload;
  void clear() => state = null;
}

final pendingShareProvider =
    NotifierProvider<PendingShare, SharedPayload?>(PendingShare.new);
