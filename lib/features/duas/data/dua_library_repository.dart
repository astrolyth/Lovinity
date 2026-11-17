import 'package:supabase_flutter/supabase_flutter.dart';

class LibraryDua {
  const LibraryDua({
    required this.id,
    required this.title,
    required this.arabic,
    required this.translation,
    required this.repeatCount,
    required this.tags,
    required this.sortOrder,
    this.transliteration,
    this.reference,
    this.category,
    this.benefit,
  });

  final String id;
  final String title;
  final String arabic;
  final String? transliteration;
  final String translation;
  final String? reference;
  final String? category;
  final int repeatCount;
  final String? benefit;
  final List<String> tags;
  final int sortOrder;

  factory LibraryDua.fromRow(Map<String, dynamic> row) => LibraryDua(
        id: row['id'] as String,
        title: row['title'] as String,
        arabic: row['arabic_text'] as String,
        transliteration: row['transliteration'] as String?,
        translation: row['translation'] as String,
        reference: row['reference'] as String?,
        category: row['category'] as String?,
        repeatCount: (row['repeat_count'] as num?)?.toInt() ?? 1,
        benefit: row['benefit'] as String?,
        tags: [for (final t in (row['tags'] as List?) ?? const []) t as String],
        sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      );
}

class DuaLibraryRepository {
  DuaLibraryRepository(this._client);
  final SupabaseClient _client;

  Future<List<LibraryDua>> fetchApproved() async {
    final rows = await _client
        .from('duas_library')
        .select()
        .eq('status', 'approved')
        .order('category')
        .order('sort_order');
    return [
      for (final r in rows) LibraryDua.fromRow(Map<String, dynamic>.from(r)),
    ];
  }
}
