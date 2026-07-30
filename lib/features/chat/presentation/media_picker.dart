// lib/features/chat/presentation/media_picker.dart
//
// Picks + compresses a photo or video for chat, and generates its embedded
// thumbnail. Lives in the presentation layer (not domain/ChatService) so
// ChatService stays a pure Dart unit with no Flutter-plugin dependency --
// same reasoning as core/notifications/push_service.dart's PushMessaging
// seam. DevicePicker itself is thin glue, not unit tested directly; the
// MediaPicker interface is what composer widget tests fake.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumb;

enum MediaSource { camera, gallery }

class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.thumbnailBytes,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final Uint8List thumbnailBytes;
}

class PickedVideo {
  const PickedVideo({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
    required this.thumbnailBytes,
  });

  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
  final Uint8List thumbnailBytes;
}

abstract class MediaPicker {
  /// Returns null if the user cancelled the picker.
  Future<PickedPhoto?> pickPhoto(MediaSource source);

  /// Returns null if the user cancelled the picker. Videos are capped at 60
  /// seconds at the picker level (no client-side re-encode).
  Future<PickedVideo?> pickVideo(MediaSource source);
}

class DevicePicker implements MediaPicker {
  final _picker = ImagePicker();

  @override
  Future<PickedPhoto?> pickPhoto(MediaSource source) async {
    final xfile = await _picker.pickImage(
      source: source == MediaSource.camera ? ImageSource.camera : ImageSource.gallery,
    );
    if (xfile == null) return null;

    final compressed = await FlutterImageCompress.compressWithFile(
      xfile.path,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
    );
    if (compressed == null) return null;

    final thumb = await FlutterImageCompress.compressWithFile(
      xfile.path,
      minWidth: 200,
      minHeight: 200,
      quality: 60,
    );
    if (thumb == null) return null;

    final decoded = await _decodeImage(compressed);
    return PickedPhoto(
      bytes: compressed,
      mimeType: 'image/jpeg',
      width: decoded.width,
      height: decoded.height,
      thumbnailBytes: thumb,
    );
  }

  @override
  Future<PickedVideo?> pickVideo(MediaSource source) async {
    final xfile = await _picker.pickVideo(
      source: source == MediaSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (xfile == null) return null;

    final bytes = await xfile.readAsBytes();

    final thumbBytes = await video_thumb.VideoThumbnail.thumbnailData(
      video: xfile.path,
      imageFormat: video_thumb.ImageFormat.JPEG,
      maxWidth: 200,
      quality: 60,
    );
    if (thumbBytes == null) return null;

    final controller = VideoPlayerController.file(File(xfile.path));
    await controller.initialize();
    final durationMs = controller.value.duration.inMilliseconds;
    await controller.dispose();

    return PickedVideo(
      bytes: bytes,
      mimeType: 'video/mp4',
      durationMs: durationMs,
      thumbnailBytes: thumbBytes,
    );
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }
}
