import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/wall_models.dart';

/// Supabase access for Our Wall. Rows are protected by RLS (couple members
/// only; authors alone may delete). Streams are realtime and re-emit the
/// full list on every change.
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

  Future<void> deleteItem(String itemId) =>
      _client.from('feed_items').delete().eq('id', itemId);

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
