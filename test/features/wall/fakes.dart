import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/wall/data/link_preview_service.dart';
import 'package:lovinity/features/wall/data/wall_repository.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';

class AddItemCall {
  AddItemCall(this.args);
  final Map<String, Object?> args;
}

class FakeWallRepository extends Fake implements WallRepository {
  final added = <AddItemCall>[];
  final reactionCalls = <String>[];
  final comments = <String>[];
  final deleted = <String>[];
  Object? throwOnAdd;
  Object? throwOnReact;

  /// When true, each reaction call waits on a gate in [reactionGates]
  /// (complete it, or completeError it to make that call fail).
  bool holdReactions = false;
  final reactionGates = <Completer<void>>[];

  /// Every reaction call as it starts, in order (before any gate/failure).
  final reactionStarts = <String>[];

  /// When set, [addComment] waits on it before recording the comment.
  Completer<void>? commentGate;

  @override
  Future<WallItem> addItem({
    required String coupleId,
    required String userId,
    String? url,
    String? title,
    String? description,
    String? imageUrl,
    required WallSource source,
    WallCollection? collection,
    String? note,
  }) async {
    if (throwOnAdd != null) throw throwOnAdd!;
    added.add(
      AddItemCall({
        'coupleId': coupleId,
        'userId': userId,
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'source': source,
        'collection': collection,
        'note': note,
      }),
    );
    return WallItem(
      id: 'new',
      coupleId: coupleId,
      addedBy: userId,
      url: url,
      title: title,
      source: source,
      collection: collection,
      note: note,
      isPinned: false,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<WallItem> addMediaItem({
    required String coupleId,
    required String userId,
    required Uint8List bytes,
    required String mimeType,
    Uint8List? thumbnailBytes,
    WallCollection? collection,
    String? note,
  }) async {
    if (throwOnAdd != null) throw throwOnAdd!;
    added.add(
      AddItemCall({
        'coupleId': coupleId,
        'userId': userId,
        'bytes': bytes,
        'mimeType': mimeType,
        'thumbnailBytes': thumbnailBytes,
        'collection': collection,
        'note': note,
      }),
    );
    return WallItem(
      id: 'new',
      coupleId: coupleId,
      addedBy: userId,
      source: mimeType.startsWith('video/')
          ? WallSource.video
          : WallSource.photo,
      collection: collection,
      note: note,
      isPinned: false,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> addReaction({
    required String coupleId,
    required String itemId,
    required String userId,
    required WallReactionKind kind,
  }) async {
    await _react('add:${kind.key}');
  }

  @override
  Future<void> removeReaction({
    required String itemId,
    required String userId,
    required WallReactionKind kind,
  }) async {
    await _react('remove:${kind.key}');
  }

  Future<void> _react(String call) async {
    reactionStarts.add(call);
    if (holdReactions) {
      final gate = Completer<void>();
      reactionGates.add(gate);
      await gate.future;
    }
    if (throwOnReact != null) throw throwOnReact!;
    reactionCalls.add(call);
  }

  @override
  Future<void> addComment({
    required String coupleId,
    required String itemId,
    required String userId,
    required String body,
  }) async {
    if (commentGate != null) await commentGate!.future;
    comments.add(body);
  }

  @override
  Future<void> deleteItem(WallItem item) async => deleted.add(item.id);

  @override
  Future<void> setPinned(String itemId, bool pinned) async {}

  @override
  Future<void> setCollection(String itemId, WallCollection? collection) async {}

  @override
  Future<void> deleteComment(String commentId) async => deleted.add(commentId);
}

class FakeLinkPreviewService extends Fake implements LinkPreviewService {
  FakeLinkPreviewService([this.handler]);
  Future<LinkPreview?> Function(String url)? handler;
  final requested = <String>[];

  @override
  Future<LinkPreview?> fetch(String url) async {
    requested.add(url);
    return handler == null ? null : handler!(url);
  }

  @override
  void close() {}
}
