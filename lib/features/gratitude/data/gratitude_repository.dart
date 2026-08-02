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

  /// Own notes plus the spouse's `reveal_to_spouse: true` notes only.
  ///
  /// The real enforcement is server-side RLS (see
  /// `supabase/migrations/20260801000001_gratitude_rls.sql`): a still-private
  /// spouse row is never returned to this client's JWT in the first place.
  /// The `.map(...)` filter below is a client-side belt-and-suspenders layer
  /// on top of that, not the mechanism that makes this safe -- `.or(...)`
  /// is not available on `SupabaseStreamFilterBuilder` in this package
  /// version (`.stream()` supports only a single eq/neq/lt/lte/gt/gte/
  /// inFilter), so it cannot express "own OR revealed" server-side from the
  /// client query itself; RLS is what actually does that job.
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
