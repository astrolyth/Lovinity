import 'package:supabase_flutter/supabase_flutter.dart';

class Dua {
  const Dua({
    required this.id,
    required this.authorId,
    required this.title,
    required this.visibility,
    required this.isAnswered,
    required this.createdAt,
    this.body,
    this.answeredAt,
    this.answeredNote,
  });

  final String id;
  final String authorId;
  final String title;
  final String? body;
  final String visibility; // 'private' | 'shared'
  final bool isAnswered;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final String? answeredNote;

  bool get isShared => visibility == 'shared';

  factory Dua.fromRow(Map<String, dynamic> row) => Dua(
        id: row['id'] as String,
        authorId: row['author_id'] as String,
        title: row['title'] as String,
        body: row['body'] as String?,
        visibility: (row['visibility'] as String?) ?? 'shared',
        isAnswered: row['is_answered'] as bool? ?? false,
        createdAt: DateTime.parse(row['created_at'] as String),
        answeredAt: row['answered_at'] == null
            ? null
            : DateTime.parse(row['answered_at'] as String),
        answeredNote: row['answered_note'] as String?,
      );
}

class DuaRepository {
  DuaRepository(this._client);
  final SupabaseClient _client;

  Stream<List<Dua>> watch(String coupleId) {
    return _client
        .from('duas')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at')
        .map((rows) => [
              for (final r in rows.reversed)
                Dua.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<void> add({
    required String coupleId,
    required String userId,
    required String title,
    String? body,
    String visibility = 'shared',
  }) async {
    await _client.from('duas').insert({
      'couple_id': coupleId,
      'author_id': userId,
      'title': title,
      if (body != null && body.isNotEmpty) 'body': body,
      'visibility': visibility,
    });
  }

  Future<void> setAnswered(String id, {String? note}) async {
    await _client.from('duas').update({
      'is_answered': true,
      'answered_at': DateTime.now().toUtc().toIso8601String(),
      if (note != null && note.isNotEmpty) 'answered_note': note,
    }).eq('id', id);
  }

  Future<void> setUnanswered(String id) async {
    await _client.from('duas').update({
      'is_answered': false,
      'answered_at': null,
      'answered_note': null,
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('duas').delete().eq('id', id);
  }
}
