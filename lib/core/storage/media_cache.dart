// lib/core/storage/media_cache.dart
//
// Where decrypted chat-attachment bytes are cached on disk, keyed by chat
// message id. A seam (not called directly as static path_provider/File calls)
// so ChatService's attachment methods stay unit-testable without a real
// Flutter plugin binding -- same reasoning as PushMessaging/PushTokenApi in
// core/notifications/push_service.dart. FileMediaCache itself is thin glue,
// not unit tested directly (same as that file's platform adapters);
// consumers are tested against a fake.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

abstract class MediaCache {
  /// Writes [bytes] to local storage keyed by [key] (the chat message id)
  /// and returns the absolute file path.
  Future<String> write(String key, Uint8List bytes);

  /// Deletes all cached decrypted attachment files. Called on account switch
  /// so a different user signing in on this device never has access to the
  /// previous user's decrypted photos/videos.
  Future<void> clear();
}

class FileMediaCache implements MediaCache {
  @override
  Future<String> write(String key, Uint8List bytes) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/chat_media/$key');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<void> clear() async {
    final dir = await getApplicationSupportDirectory();
    final mediaDir = Directory('${dir.path}/chat_media');
    if (await mediaDir.exists()) {
      await mediaDir.delete(recursive: true);
    }
  }
}
