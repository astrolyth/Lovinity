// lib/features/chat/data/chat_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/crypto/signal_session_service.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

class ChatRepository {
  ChatRepository(this._client);
  final SupabaseClient _client;

  Future<({String messageId, DateTime createdAt})> sendEnvelopes({
    required int senderDeviceNum,
    required List<EncryptedCopy> copies,
    String? messageId,
  }) async {
    final envelopes = [
      for (final c in copies)
        {
          'recipient_id': c.userId,
          'recipient_device_num': c.deviceNum,
          'cipher_type': c.cipherType,
          'ciphertext': _hex(c.ciphertext),
        }
    ];
    final rows = await _client.rpc('send_message', params: {
      'p_sender_device_num': senderDeviceNum,
      'p_envelopes': envelopes,
      if (messageId != null) 'p_message_id': messageId,
    });
    final row = (rows is List) ? rows.first : rows;
    final m = Map<String, dynamic>.from(row as Map);
    return (
      messageId: m['message_id'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  Stream<List<Map<String, dynamic>>> watchInbox(String userId) {
    // Realtime only signals that envelopes changed; re-fetch the rows over
    // REST so `ciphertext` bytea is the reliable Postgres `\x`-hex form the
    // decoder expects. Supabase Realtime's bytea encoding isn't guaranteed to
    // match, and a mis-decoded ciphertext fails silently (it gets
    // dead-lettered), so we never decrypt from the realtime payload's bytea.
    // The re-fetch also means already-deleted envelopes never reappear.
    return _client
        .from('message_envelopes')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .asyncMap((_) async {
      final rows = await _client
          .from('message_envelopes')
          .select()
          .eq('recipient_id', userId);
      return [for (final r in rows) Map<String, dynamic>.from(r as Map)];
    });
  }

  Stream<List<Map<String, dynamic>>> watchMyMessages(String coupleId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [for (final r in rows) Map<String, dynamic>.from(r)]);
  }

  Future<void> deleteEnvelope(String envelopeId) =>
      _client.from('message_envelopes').delete().eq('id', envelopeId);

  Future<void> markDelivered(String messageId) =>
      _client.rpc('mark_delivered', params: {'p_message_id': messageId});

  Future<void> markRead(String messageId) =>
      _client.rpc('mark_read', params: {'p_message_id': messageId});
}
