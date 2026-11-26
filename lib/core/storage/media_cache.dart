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
}

/// Decrypted attachments for ONE account, under `chat_media/<userId>/`, so
/// accounts sharing a device never share decrypted files (same per-account
/// split as [SignalDb.forUser]).
class FileMediaCache implements MediaCache {
  FileMediaCache(this.userId);
  final String userId;

  @override
  Future<String> write(String key, Uint8List bytes) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/chat_media/$userId/$key');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
