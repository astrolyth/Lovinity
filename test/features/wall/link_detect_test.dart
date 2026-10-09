import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/wall/domain/link_detect.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';

void main() {
  group('extractFirstUrl', () {
    test('finds a URL inside text', () {
      expect(extractFirstUrl('Check this out! https://youtu.be/abc123 so good'),
          'https://youtu.be/abc123');
    });
    test('strips trailing punctuation and an unbalanced paren', () {
      expect(extractFirstUrl('(see https://example.com/a).'), 'https://example.com/a');
      expect(extractFirstUrl('wow https://example.com/b!!'), 'https://example.com/b');
    });
    test('keeps a balanced paren that is part of the path', () {
      expect(extractFirstUrl('https://en.wikipedia.org/wiki/Foo_(bar)'),
          'https://en.wikipedia.org/wiki/Foo_(bar)');
    });
    test('returns the first of several URLs', () {
      expect(extractFirstUrl('a http://one.example b https://two.example'),
          'http://one.example');
    });
    test('null when there is no usable URL', () {
      expect(extractFirstUrl('no links here'), isNull);
      expect(extractFirstUrl('https://'), isNull);
      expect(extractFirstUrl('ftp://files.example/x'), isNull);
    });
  });

  group('classifyUrl', () {
    test('recognises video hosts including subdomains and short links', () {
      expect(classifyUrl('https://www.youtube.com/watch?v=1'), WallSource.youtube);
      expect(classifyUrl('https://m.youtube.com/watch?v=1'), WallSource.youtube);
      expect(classifyUrl('https://youtu.be/1'), WallSource.youtube);
      expect(classifyUrl('https://www.instagram.com/reel/C9x/'), WallSource.instagram);
      expect(classifyUrl('https://vm.tiktok.com/ZM123/'), WallSource.tiktok);
    });
    test('look-alike hosts are articles', () {
      expect(classifyUrl('https://notyoutube.com/x'), WallSource.article);
      expect(classifyUrl('https://example.com/recipe'), WallSource.article);
    });
  });

  group('parseSharedText', () {
    test('text with a URL yields only the URL', () {
      final r = parseSharedText('Look at this https://youtu.be/x');
      expect(r.url, 'https://youtu.be/x');
      expect(r.note, isNull);
    });
    test('text without a URL becomes a trimmed, capped note', () {
      final r = parseSharedText('  remind me to call your mum  ');
      expect(r.url, isNull);
      expect(r.note, 'remind me to call your mum');
      expect(parseSharedText('x' * 1500).note!.length, 1000);
    });
    test('blank text yields nothing', () {
      final r = parseSharedText('   ');
      expect(r.url, isNull);
      expect(r.note, isNull);
    });
  });
}
