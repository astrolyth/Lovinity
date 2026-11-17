import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';
import 'package:lovinity/features/duas/domain/dua_search.dart';

LibraryDua d(String id, String title,
        {String? translit, String? category}) =>
    LibraryDua(
      id: id,
      title: title,
      arabic: 'x',
      transliteration: translit,
      translation: '',
      category: category,
      repeatCount: 1,
      tags: const [],
      sortOrder: 0,
    );

void main() {
  test('normalizeForSearch strips diacritics', () {
    expect(normalizeForSearch('Ṣabāḥ'), 'sabah');
    expect(normalizeForSearch("ʿIlm ’a"), 'ilm a');
  });

  final eating = d('1', 'Supplication Before Eating', category: 'food');
  final travel = d('2', 'Travel Supplication', category: 'travel');
  final morning =
      d('3', 'Upon Entering The Morning', translit: 'aṣbaḥnā', category: 'morning');
  final all = [eating, travel, morning];

  test('searchLibrary', () {
    expect(searchLibrary(all, 'EATING'), [eating]);
    expect(searchLibrary(all, 'eating before'), [eating]);
    expect(searchLibrary(all, 'eating travel'), isEmpty);
    expect(searchLibrary(all, 'asbahna'), [morning]);
    expect(searchLibrary(all, '', category: 'travel'), [travel]);
    expect(searchLibrary(const [], 'x'), isEmpty);
  });
}
