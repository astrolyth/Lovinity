import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/moment.dart';

const _bucket = 'moments';

/// Supabase access for Moments. RLS: couple members read; sender inserts and
/// deletes; viewed_at only via the mark_moment_viewed RPC.
class MomentsRepository {
  MomentsRepository(this._client);

  final SupabaseClient _client;

  Stream<List<Moment>> watch(String coupleId) => _client
      .from('moments')
      .stream(primaryKey: ['id'])
      .eq('couple_id', coupleId)
      .map(
        (rows) =>
            [for (final r in rows) Moment.fromRow(Map<String, dynamic>.from(r))]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );

  /// Uploads first, then inserts; a failed insert removes the uploaded files.
  Future<void> send({
    required String coupleId,
    required String userId,
    required Uint8List bytes,
    required String mimeType,
    Uint8List? thumbnailBytes,
    String? caption,
  }) async {
    final isVideo = mimeType.startsWith('video/');
    final id = const Uuid().v4();
    final dir = '$coupleId/$id';
    final mediaPath = '$dir/media.${isVideo ? 'mp4' : 'jpg'}';
    final thumbPath = isVideo && thumbnailBytes != null
        ? '$dir/thumb.jpg'
        : null;
    final bucket = _client.storage.from(_bucket);
    final uploaded = <String>[];
    var insertSent = false;
    try {
      await bucket.uploadBinary(
        mediaPath,
        bytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: false),
      );
      uploaded.add(mediaPath);
      if (thumbPath != null) {
        await bucket.uploadBinary(
          thumbPath,
          thumbnailBytes!,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
        uploaded.add(thumbPath);
      }
      insertSent = true;
      final trimmed = caption?.trim();
      await _client.from('moments').insert({
        'id': id,
        'couple_id': coupleId,
        'sender_id': userId,
        'media_path': mediaPath,
        'media_mime': mimeType,
        'thumb_path': thumbPath,
        'caption': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      });
    } catch (e) {
      if (insertSent && e is! PostgrestException) {
        // The response may have been lost after the row committed; keep its files.
        try {
          final saved = await _client
              .from('moments')
              .select('id')
              .eq('id', id)
              .maybeSingle();
          if (saved != null) return;
        } catch (_) {}
      }
      if (uploaded.isNotEmpty) {
        try {
          await bucket.remove(uploaded);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// All replies for the couple, oldest first, realtime.
  Stream<List<MomentReply>> watchReplies(String coupleId) => _client
      .from('moment_replies')
      .stream(primaryKey: ['id'])
      .eq('couple_id', coupleId)
      .map(
        (rows) => [
          for (final r in rows)
            MomentReply.fromRow(Map<String, dynamic>.from(r)),
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  /// Adds the emoji, or removes it if [existing] is this user's same emoji.
  Future<void> toggleReaction({
    required Moment moment,
    required String userId,
    required String emoji,
    MomentReply? existing,
  }) async {
    if (existing != null) {
      await _client.from('moment_replies').delete().eq('id', existing.id);
      return;
    }
    // Idempotent: a double tap must not fail on the unique index.
    await _client
        .from('moment_replies')
        .upsert(
          {
            'moment_id': moment.id,
            'couple_id': moment.coupleId,
            'author_id': userId,
            'emoji': emoji,
          },
          onConflict: 'moment_id,author_id,emoji',
          ignoreDuplicates: true,
        );
  }

  Future<void> comment({
    required Moment moment,
    required String userId,
    required String body,
  }) => _client.from('moment_replies').insert({
    'moment_id': moment.id,
    'couple_id': moment.coupleId,
    'author_id': userId,
    'body': body.trim(),
  });

  Future<void> deleteReply(String id) =>
      _client.from('moment_replies').delete().eq('id', id);

  Future<void> markViewed(String id) =>
      _client.rpc('mark_moment_viewed', params: {'p_id': id});

  Future<String> signedUrl(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, 3600);

  /// Sender only (RLS). Row first, then files, best effort.
  Future<void> delete(Moment m) async {
    await _client.from('moments').delete().eq('id', m.id);
    try {
      await _client.storage.from(_bucket).remove([m.mediaPath, ?m.thumbPath]);
    } catch (_) {
      // shortcut: a failed file delete leaves an orphan in storage; add a cleanup job if storage cost matters.
    }
  }
}
