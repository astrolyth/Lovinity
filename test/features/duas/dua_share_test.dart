import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/duas/data/dua_library_repository.dart';
import 'package:lovinity/features/duas/domain/dua_share.dart';

void main() {
  test('formatDuaForChat full', () {
    const d = LibraryDua(
      id: '1',
      title: 'Eating',
      arabic: 'AR',
      transliteration: 'tr',
      translation: 'En',
      reference: 'Bukhari',
      repeatCount: 1,
      tags: [],
      sortOrder: 0,
    );
    expect(formatDuaForChat(d), '🤲 Eating\nAR\ntr\n"En"\n— Bukhari');
    expect(duaListBody(d), 'AR\n\nEn\n\n— Bukhari');
  });

  test('formatDuaForChat omits null lines', () {
    const d = LibraryDua(
      id: '1',
      title: 'Eating',
      arabic: 'AR',
      translation: 'En',
      repeatCount: 1,
      tags: [],
      sortOrder: 0,
    );
    final s = formatDuaForChat(d);
    expect(s, isNot(contains('null')));
    expect(s, isNot(contains('—')));
    expect(duaListBody(d), 'AR\n\nEn');
  });
}
