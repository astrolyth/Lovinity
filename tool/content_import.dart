// Pure helpers for tool/import_islamic_content.dart (no Flutter imports).

int parseRepeatCount(String? notes) {
  final m = RegExp(r'(\d+)\s*x', caseSensitive: false).firstMatch(notes ?? '');
  return m == null ? 1 : int.parse(m.group(1)!);
}

class ImportRow {
  ImportRow({
    required this.source,
    required this.sourceId,
    required this.title,
    required this.arabic,
    required this.transliteration,
    required this.translation,
    required this.reference,
    required this.category,
    required this.repeatCount,
    required this.benefit,
    required this.tags,
    required this.sortOrder,
    required this.status,
  });
  String source;
  String sourceId;
  String title;
  String arabic;
  String? transliteration;
  String translation;
  String? reference;
  String category;
  int repeatCount;
  String? benefit;
  List<String> tags;
  int sortOrder;
  String status;
}

const _adhkarCategory = {
  'morning-dhikr': 'morning',
  'evening-dhikr': 'evening',
  'dhikr-after-salah': 'after_prayer',
};

List<ImportRow> rowsForSet(
  String set,
  List<Map<String, dynamic>> items,
  Map<String, dynamic> tagsJson,
) {
  final rows = <ImportRow>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final id = '$set/$i';
    String category;
    List<String> tags;
    final adhkar = _adhkarCategory[set];
    final override = tagsJson[id] as Map<String, dynamic>?;
    if (adhkar != null) {
      category = adhkar;
      tags = ['dhikr', adhkar, ...?(override?['tags'] as List?)?.cast<String>()];
    } else {
      if (override == null) throw StateError('untagged: $id');
      category = override['category'] as String;
      tags = (override['tags'] as List).cast<String>();
    }
    String? nonEmpty(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final ref = nonEmpty(it['source']);
    rows.add(ImportRow(
      source: 'fitrahive',
      sourceId: id,
      title: it['title'] as String,
      arabic: it['arabic'] as String,
      transliteration: it['latin'] as String?,
      translation: it['translation'] as String,
      reference: ref,
      category: category,
      repeatCount: parseRepeatCount(it['notes'] as String?),
      benefit: (it['fawaid'] ?? it['benefits']) as String?,
      tags: tags.toSet().toList(),
      sortOrder: i,
      status: ref != null ? 'approved' : 'pending',
    ));
  }
  return rows;
}

String _q(String? s) => s == null ? 'null' : "'${s.replaceAll("'", "''")}'";

String toSqlUpsert(List<ImportRow> rows) {
  const cols = [
    'source', 'source_id', 'title', 'arabic_text', 'transliteration',
    'translation', 'reference', 'category', 'repeat_count', 'benefit',
    'tags', 'sort_order', 'status',
  ];
  // status is deliberately absent from the update list: a re-import must not
  // re-approve a row a human rejected.
  final updatable = cols.where((c) => c != 'source' && c != 'source_id' && c != 'status');
  final values = rows.map((r) {
    final tags = 'array[${r.tags.map(_q).join(',')}]::text[]';
    return '(${[
      _q(r.source), _q(r.sourceId), _q(r.title), _q(r.arabic),
      _q(r.transliteration), _q(r.translation), _q(r.reference),
      _q(r.category), r.repeatCount, _q(r.benefit), tags, r.sortOrder,
      _q(r.status),
    ].join(', ')})';
  }).join(',\n');
  return 'insert into public.duas_library (${cols.join(', ')}) values\n'
      '$values\n'
      'on conflict (source, source_id) do update set\n'
      '${updatable.map((c) => '  $c = excluded.$c').join(',\n')};\n';
}
