import '../data/dua_library_repository.dart';

const adhkarCategories = {'morning', 'evening', 'after_prayer'};

const _fold = {
  'ā': 'a', 'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a',
  'ē': 'e', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'ī': 'i', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ō': 'o', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o',
  'ū': 'u', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ṣ': 's', 'ḥ': 'h', 'ṭ': 't', 'ḍ': 'd', 'ẓ': 'z',
  'ʿ': '', 'ʾ': '', "'": '', '’': '',
};

String normalizeForSearch(String s) => s
    .toLowerCase()
    .split('')
    .map((c) => _fold[c] ?? c)
    .join();

List<LibraryDua> searchLibrary(List<LibraryDua> all, String query,
    {String? category}) {
  final pool =
      category == null ? all : all.where((d) => d.category == category);
  final terms = normalizeForSearch(query)
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  return [
    for (final d in pool)
      if (terms.isEmpty ||
          _all(
              normalizeForSearch([
                d.title,
                d.translation,
                d.transliteration ?? '',
                d.category ?? '',
                ...d.tags,
              ].join(' ')),
              terms))
        d,
  ];
}

bool _all(String hay, Iterable<String> terms) => terms.every(hay.contains);
