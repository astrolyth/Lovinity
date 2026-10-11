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
    added.add(AddItemCall({
      'coupleId': coupleId, 'userId': userId, 'url': url, 'title': title,
      'description': description, 'imageUrl': imageUrl, 'source': source,
      'collection': collection, 'note': note,
    }));
    return WallItem(
      id: 'new', coupleId: coupleId, addedBy: userId, url: url, title: title,
      source: source, collection: collection, note: note, isPinned: false,
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
    if (throwOnReact != null) throw throwOnReact!;
    reactionCalls.add('add:${kind.key}');
  }

  @override
  Future<void> removeReaction({
    required String itemId,
    required String userId,
    required WallReactionKind kind,
  }) async {
    if (throwOnReact != null) throw throwOnReact!;
    reactionCalls.add('remove:${kind.key}');
  }

  @override
  Future<void> addComment({
    required String coupleId,
    required String itemId,
    required String userId,
    required String body,
  }) async =>
      comments.add(body);

  @override
  Future<void> deleteItem(String itemId) async => deleted.add(itemId);

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
