import 'package:supabase_flutter/supabase_flutter.dart';

class GratitudeNote {
  const GratitudeNote({
    required this.id,
    required this.authorId,
    required this.body,
    required this.revealToSpouse,
    required this.createdAt,
    this.revealedAt,
  });

  final String id;
  final String authorId;
  final String body;
  final bool revealToSpouse;
  final DateTime createdAt;
  final DateTime? revealedAt;

  factory GratitudeNote.fromRow(Map<String, dynamic> row) => GratitudeNote(
        id: row['id'] as String,
        authorId: row['author_id'] as String,
        body: row['body'] as String,
        revealToSpouse: row['reveal_to_spouse'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
        revealedAt: row['revealed_at'] == null
            ? null
            : DateTime.parse(row['revealed_at'] as String),
      );
}

class GratitudeRepository {
  GratitudeRepository(this._client);
  final SupabaseClient _client;

  /// Own notes plus the spouse's `reveal_to_spouse: true` notes only -- a
  /// still-private spouse note must never reach this device at all (fixes
  /// a real leak: the previous unfiltered query relied on the UI alone to
  /// hide `note.body`, but the raw text was already delivered to the
  /// client). Supabase's `.or(...)` filter expresses this server-side.
  Stream<List<GratitudeNote>> watchAll({
    required String coupleId,
    required String selfUserId,
  }) {
    return _client
        .from('gratitude_notes')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at')
        .map((rows) => [
              for (final r in rows.reversed)
                GratitudeNote.fromRow(Map<String, dynamic>.from(r)),
            ])
        .map((notes) => [
              for (final n in notes)
                if (n.authorId == selfUserId || n.revealToSpouse) n,
            ]);
  }

  Future<void> add({
    required String coupleId,
    required String userId,
    required String body,
    required bool revealToSpouse,
  }) async {
    await _client.from('gratitude_notes').insert({
      'couple_id': coupleId,
      'author_id': userId,
      'body': body,
      'reveal_to_spouse': revealToSpouse,
      if (revealToSpouse)
        'revealed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> reveal(String id) async {
    await _client.from('gratitude_notes').update({
      'reveal_to_spouse': true,
      'revealed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }
}
