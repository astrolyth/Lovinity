import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';

void main() {
  test('fromRow maps every column', () {
    final x = LibraryDua.fromRow({
      'id': 'a',
      'title': 't',
      'arabic_text': 'ar',
      'transliteration': 'tr',
      'translation': 'en',
      'reference': 'ref',
      'category': 'food',
      'repeat_count': 3,
      'benefit': 'b',
      'tags': <dynamic>['x', 'y'],
      'sort_order': 7,
    });
    expect(x.id, 'a');
    expect(x.title, 't');
    expect(x.arabic, 'ar');
    expect(x.transliteration, 'tr');
    expect(x.translation, 'en');
    expect(x.reference, 'ref');
    expect(x.category, 'food');
    expect(x.repeatCount, 3);
    expect(x.benefit, 'b');
    expect(x.tags, ['x', 'y']);
    expect(x.sortOrder, 7);
  });

  test('defaults', () {
    final x = LibraryDua.fromRow({
      'id': 'a',
      'title': 't',
      'arabic_text': 'ar',
      'translation': 'en',
    });
    expect(x.tags, isEmpty);
    expect(x.repeatCount, 1);
    expect(x.sortOrder, 0);
  });
}
