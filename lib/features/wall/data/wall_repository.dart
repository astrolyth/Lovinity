import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:uuid/uuid.dart';

import '../domain/wall_models.dart';

/// Supabase access for Our Wall. Rows are protected by RLS (couple members
/// only; authors alone may delete). Streams are realtime and re-emit the
/// full list on every change.
const _bucket = 'wall-media';

class WallRepository {
  WallRepository(this._client);

  final SupabaseClient _client;

  Stream<List<WallItem>> watchItems(String coupleId) {
    return _client
        .from('feed_items')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows) WallItem.fromRow(Map<String, dynamic>.from(r)),
            ]..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<WallReaction>> watchReactions(String coupleId) {
    return _client
        .from('feed_reactions')
        .stream(primaryKey: ['item_id', 'user_id', 'reaction'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                ?WallReaction.tryFromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Stream<List<WallComment>> watchComments(String coupleId) {
    return _client
        .from('feed_comments')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows) WallComment.fromRow(Map<String, dynamic>.from(r)),
            ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

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
    final row = await _client
        .from('feed_items')
        .insert({
          'couple_id': coupleId,
          'added_by': userId,
          'url': url,
          'title': title,
          'description': description,
          'image_url': imageUrl,
          'source': source.key,
          'collection': collection?.key,
          'note': note,
        })
        .select()
        .single();
    return WallItem.fromRow(row);
  }

  /// One medium per post. Uploads first, then inserts; a failed insert removes
  /// the uploaded files again.
  Future<WallItem> addMediaItem({
    required String coupleId,
    required String userId,
    required Uint8List bytes,
    required String mimeType,
    Uint8List? thumbnailBytes,
    WallCollection? collection,
    String? note,
  }) async {
    final isVideo = mimeType.startsWith('video/');
    final id = const Uuid().v4();
    final dir = '$coupleId/$id';
    final mediaPath = '$dir/media.${isVideo ? 'mp4' : 'jpg'}';
    final thumbPath = '$dir/thumb.jpg';
    final bucket = _client.storage.from(_bucket);
    final uploaded = <String>[];
    try {
      await bucket.uploadBinary(mediaPath, bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false));
      uploaded.add(mediaPath);
      if (isVideo && thumbnailBytes != null) {
        await bucket.uploadBinary(thumbPath, thumbnailBytes,
            fileOptions:
                const FileOptions(contentType: 'image/jpeg', upsert: false));
        uploaded.add(thumbPath);
      }
      final row = await _client
          .from('feed_items')
          .insert({
            'id': id,
            'couple_id': coupleId,
            'added_by': userId,
            'source': isVideo ? WallSource.video.key : WallSource.photo.key,
            'media_url': mediaPath,
            'media_mime': mimeType,
            'collection': collection?.key,
            'note': note,
          })
          .select()
          .single();
      return WallItem.fromRow(row);
    } catch (_) {
      if (uploaded.isNotEmpty) {
        try {
          await bucket.remove(uploaded);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<String> signedUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, 3600);

  /// Only the author can delete (RLS). Row first, then files, best effort.
  Future<void> deleteItem(WallItem item) async {
    await _client.from('feed_items').delete().eq('id', item.id);
    if (!item.hasMedia) return;
    try {
      await _client.storage.from(_bucket).remove([item.mediaPath!, ?item.thumbPath]);
    } catch (_) {
      // shortcut: a failed file delete leaves an orphan in storage; add a cleanup job if storage cost matters.
    }
  }

  Future<void> setPinned(String itemId, bool pinned) =>
      _client.from('feed_items').update({'is_pinned': pinned}).eq('id', itemId);

  Future<void> setCollection(String itemId, WallCollection? collection) => _client
      .from('feed_items')
      .update({'collection': collection?.key}).eq('id', itemId);

  /// Idempotent: a double tap must not fail on the primary key.
  Future<void> addReaction({
    required String coupleId,
    required String itemId,
    required String userId,
    required WallReactionKind kind,
  }) =>
      _client.from('feed_reactions').upsert(
        {
          'item_id': itemId,
          'user_id': userId,
          'reaction': kind.key,
          'couple_id': coupleId,
        },
        onConflict: 'item_id,user_id,reaction',
        ignoreDuplicates: true,
      );

  Future<void> removeReaction({
    required String itemId,
    required String userId,
    required WallReactionKind kind,
  }) =>
      _client
          .from('feed_reactions')
          .delete()
          .eq('item_id', itemId)
          .eq('user_id', userId)
          .eq('reaction', kind.key);

  Future<void> addComment({
    required String coupleId,
    required String itemId,
    required String userId,
    required String body,
  }) =>
      _client.from('feed_comments').insert({
        'item_id': itemId,
        'couple_id': coupleId,
        'author_id': userId,
        'body': body,
      });

  Future<void> deleteComment(String commentId) =>
      _client.from('feed_comments').delete().eq('id', commentId);
}
