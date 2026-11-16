import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/letter_crypto.dart';

/// Renders bytes as a Postgres `bytea` hex literal, `\x` prefix included.
///
/// The prefix is load-bearing. `ChatRepository` passes BARE hex because its
/// value goes through an RPC that calls `decode(..., 'hex')` explicitly
/// (`20260719000001_send_message_client_id.sql:47`). A direct PostgREST insert
/// has no such decode: the string hits Postgres's own `bytea` input parser,
/// which treats an unprefixed value as the legacy *escape* format and stores
/// the ASCII of the hex digits rather than the bytes they denote. The row then
/// round-trips to twice the length and fails GCM authentication, which
/// presents as a tampering error rather than an encoding one.
String _byteaLiteral(List<int> b) =>
    '\\x${b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}';

Uint8List _fromHex(Object? value) {
  if (value is! String) return Uint8List(0);
  final hex = value.startsWith('\\x') ? value.substring(2) : value;
  return Uint8List.fromList([
    for (var i = 0; i + 1 < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// A letter's metadata, without its body.
///
/// The body is deliberately absent: for a sealed letter the server will not
/// return it at all (the RLS policy in `20260807000004_future_letters_seal.sql`
/// withholds the row from the recipient until `unlock_at`), and for an opened
/// one it must be fetched over REST rather than read from a realtime payload —
/// Supabase Realtime's bytea encoding is not guaranteed to match Postgres's
/// `\x` hex form, and a mis-decoded ciphertext fails authentication in a way
/// that looks like tampering.
class LetterSummary {
  const LetterSummary({
    required this.id,
    required this.authorId,
    required this.unlockAt,
    required this.createdAt,
    this.recipientId,
    this.unlockedAt,
  });

  final String id;
  final String authorId;

  /// Null means the letter is for both of them.
  final String? recipientId;
  final DateTime unlockAt;
  final DateTime? unlockedAt;
  final DateTime createdAt;

  bool isUnlockedAt(DateTime now) => !unlockAt.isAfter(now);

  Duration timeUntilUnlock(DateTime now) => unlockAt.difference(now);

  factory LetterSummary.fromRow(Map<String, dynamic> row) => LetterSummary(
        id: row['id'] as String,
        authorId: row['author_id'] as String,
        recipientId: row['recipient_id'] as String?,
        unlockAt: DateTime.parse(row['unlock_at'] as String),
        unlockedAt: row['unlocked_at'] == null
            ? null
            : DateTime.parse(row['unlocked_at'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

class LetterRepository {
  LetterRepository(this._client);

  final SupabaseClient _client;

  /// Letters visible to this user.
  ///
  /// What comes back is already filtered by RLS: your own letters always, plus
  /// the spouse's only once they have unlocked. A sealed letter written *to*
  /// you is simply absent — which is the point, and why the UI cannot show a
  /// countdown for a surprise you are not supposed to know exists.
  Stream<List<LetterSummary>> watchLetters({required String coupleId}) {
    return _client
        .from('future_letters')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('unlock_at')
        .map((rows) => [
              for (final r in rows)
                LetterSummary.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Fetches and decrypts one letter's body.
  ///
  /// Returns null when the server declines to return the row — which is the
  /// normal, expected outcome for a letter that has not unlocked yet, not an
  /// error to surface.
  Future<String?> openBody({
    required String letterId,
    required Uint8List letterKey,
  }) async {
    final row = await _client
        .from('future_letters')
        .select('body_ciphertext')
        .eq('id', letterId)
        .maybeSingle();
    if (row == null) return null;

    final bytes = _fromHex(row['body_ciphertext']);
    if (bytes.isEmpty) return null;
    return openLetter(
      sealed: SealedLetter.fromBytes(bytes),
      key: letterKey,
    );
  }

  Future<String> seal({
    required String coupleId,
    required String authorId,
    required String body,
    required DateTime unlockAt,
    required Uint8List letterKey,
    String? recipientId,
  }) async {
    final sealed = await sealLetter(body: body, key: letterKey);
    final row = await _client
        .from('future_letters')
        .insert({
          'couple_id': coupleId,
          'author_id': authorId,
          if (recipientId != null) 'recipient_id': recipientId,
          'body_ciphertext': _byteaLiteral(sealed.toBytes()),
          'unlock_at': unlockAt.toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Stamps the moment a letter was actually read.
  ///
  /// Permitted by RLS only for letters that have genuinely unlocked, so this
  /// cannot be used to pry one open early.
  Future<void> markOpened(String letterId) async {
    await _client.from('future_letters').update({
      'unlocked_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', letterId);
  }

  /// Withdraws a letter. RLS restricts this to the author, before unlock.
  Future<void> withdraw(String letterId) async {
    await _client.from('future_letters').delete().eq('id', letterId);
  }
}
