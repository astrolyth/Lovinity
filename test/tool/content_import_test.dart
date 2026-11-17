import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/content_import.dart';

Map<String, dynamic> _item({String source = 'HR. Abu Dawud No. 4241', String title = 'T'}) => {
      'title': title,
      'arabic': 'ع',
      'latin': 'l',
      'translation': 't',
      'notes': 'Recite 3x',
      'fawaid': 'f',
      'source': source,
    };

void main() {
  test('parseRepeatCount', () {
    expect(parseRepeatCount('Recite 3x'), 3);
    expect(parseRepeatCount('Read 100X a day'), 100);
    expect(parseRepeatCount(null), 1);
    expect(parseRepeatCount('Recite once'), 1);
  });

  test('adhkar row mapping', () {
    final r = rowsForSet('morning-dhikr', [_item()], {}).single;
    expect(r.category, 'morning');
    expect(r.repeatCount, 3);
    expect(r.status, 'approved');
    expect(r.sourceId, 'morning-dhikr/0');
    expect(r.tags, contains('morning'));
  });

  test('blank source is pending', () {
    expect(rowsForSet('morning-dhikr', [_item(source: '  ')], {}).single.status, 'pending');
  });

  test('untagged library item throws', () {
    expect(() => rowsForSet('daily-dua', [_item()], {}), throwsStateError);
  });

  test('toSqlUpsert escapes and never updates status', () {
    final sql = toSqlUpsert(rowsForSet('morning-dhikr', [_item(title: "Allah's mercy")], {}));
    expect(sql, contains("'Allah''s mercy'"));
    expect(sql, contains('on conflict (source, source_id) do update'));
    expect(sql.split('do update set').last, isNot(contains('status')));
  });

  test('tags file covers rule tags', () {
    final json = jsonDecode(File('tool/content_tags.json').readAsStringSync()) as Map<String, dynamic>;
    final all = {for (final v in json.values) ...(v['tags'] as List).cast<String>()};
    for (final t in ['distress', 'protection', 'grief', 'gratitude', 'sleep', 'dhikr', 'fasting', 'travel', 'marriage']) {
      expect(all, contains(t));
    }
    expect(json.length, 46);
  });
}
