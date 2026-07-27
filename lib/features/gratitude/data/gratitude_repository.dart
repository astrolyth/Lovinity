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

  Stream<List<GratitudeNote>> watchAll(String coupleId) {
    return _client
        .from('gratitude_notes')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at')
        .map((rows) => [
              for (final r in rows.reversed)
                GratitudeNote.fromRow(Map<String, dynamic>.from(r)),
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
