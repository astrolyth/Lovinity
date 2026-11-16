import 'package:supabase_flutter/supabase_flutter.dart';

/// A recipe the couple has saved.
class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    required this.steps,
    required this.createdAt,
    this.sourceUrl,
    this.halalNotes,
  });

  final String id;
  final String title;

  /// Where it came from — a feed item, a website. Kept so a saved recipe can
  /// always be traced back rather than becoming an orphaned copy.
  final String? sourceUrl;
  final List<String> ingredients;
  final List<String> steps;

  /// Substitutions or cautions (gelatine, vanilla extract, wine vinegar).
  final String? halalNotes;
  final DateTime createdAt;

  factory Recipe.fromRow(Map<String, dynamic> row) => Recipe(
        id: row['id'] as String,
        title: row['title'] as String,
        sourceUrl: row['source_url'] as String?,
        ingredients: _stringList(row['ingredients']),
        steps: _stringList(row['steps']),
        halalNotes: row['halal_notes'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  static List<String> _stringList(Object? raw) => [
        for (final v in (raw as List? ?? const []))
          if (v != null && v.toString().trim().isNotEmpty) v.toString(),
      ];
}

class RecipeRepository {
  RecipeRepository(this._client);

  final SupabaseClient _client;

  Stream<List<Recipe>> watchAll({required String coupleId}) {
    return _client
        .from('recipes')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('created_at')
        .map((rows) => [
              for (final r in rows.reversed)
                Recipe.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<String> save({
    required String coupleId,
    required String title,
    List<String> ingredients = const [],
    List<String> steps = const [],
    String? sourceUrl,
    String? halalNotes,
  }) async {
    final row = await _client
        .from('recipes')
        .insert({
          'couple_id': coupleId,
          'title': title,
          'ingredients': ingredients,
          'steps': steps,
          if (sourceUrl != null && sourceUrl.isNotEmpty) 'source_url': sourceUrl,
          if (halalNotes != null && halalNotes.isNotEmpty)
            'halal_notes': halalNotes,
        })
        .select()
        .single();
    return row['id'] as String;
  }

  Future<void> update({
    required String id,
    required String title,
    List<String> ingredients = const [],
    List<String> steps = const [],
    String? sourceUrl,
    String? halalNotes,
  }) async {
    await _client.from('recipes').update({
      'title': title,
      'ingredients': ingredients,
      'steps': steps,
      'source_url': sourceUrl,
      'halal_notes': halalNotes,
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('recipes').delete().eq('id', id);
  }
}
