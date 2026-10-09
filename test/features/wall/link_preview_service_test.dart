import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lovinity/features/wall/data/link_preview_service.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';

http.Response _resp(String body,
        {int status = 200, String type = 'text/html; charset=utf-8'}) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': type});

void main() {
  group('parsers', () {
    test('parseOEmbed reads title, thumbnail and provider', () {
      final p = parseOEmbed(jsonEncode({
        'title': 'The 10-minute habit',
        'thumbnail_url': 'https://i.ytimg.com/vi/x/hq.jpg',
        'provider_name': 'YouTube',
      }))!;
      expect(p.title, 'The 10-minute habit');
      expect(p.imageUrl, 'https://i.ytimg.com/vi/x/hq.jpg');
      expect(p.siteName, 'YouTube');
    });

    test('parseOEmbed returns null for junk', () {
      expect(parseOEmbed('not json'), isNull);
      expect(parseOEmbed('{}'), isNull);
    });

    test('parseHtmlPreview prefers Open Graph and decodes entities', () {
      final p = parseHtmlPreview('''
        <html><head>
          <title>Fallback</title>
          <meta property="og:title" content="Lamb biryani &amp; raita">
          <meta property="og:description" content="  Slow-cooked,   fragrant. ">
          <meta property="og:image" content="https://cdn.example/b.jpg">
          <meta property="og:site_name" content="Halal Kitchen">
        </head></html>''', baseUrl: Uri.parse('https://kitchen.example/r/1'))!;
      expect(p.title, 'Lamb biryani & raita');
      expect(p.description, 'Slow-cooked, fragrant.');
      expect(p.imageUrl, 'https://cdn.example/b.jpg');
      expect(p.siteName, 'Halal Kitchen');
    });

    test('resolves relative og:image against the page URL', () {
      final p = parseHtmlPreview(
        '<meta property="og:image" content="/img/a.png"><title>T</title>',
        baseUrl: Uri.parse('https://site.example/posts/9'),
      )!;
      expect(p.imageUrl, 'https://site.example/img/a.png');
    });

    test('falls back to twitter tags then <title>', () {
      final p = parseHtmlPreview(
        '<meta name="twitter:title" content="Tw title"><meta name="twitter:image" content="https://x.example/i.png">',
        baseUrl: Uri.parse('https://x.example'),
      )!;
      expect(p.title, 'Tw title');
      expect(p.imageUrl, 'https://x.example/i.png');
      expect(
        parseHtmlPreview('<title> Only   title </title>',
                baseUrl: Uri.parse('https://x.example'))!
            .title,
        'Only title',
      );
    });

    test('returns null when the page has nothing usable', () {
      expect(parseHtmlPreview('<html><body>hi</body></html>',
          baseUrl: Uri.parse('https://x.example')), isNull);
    });

    test('caps title length at 300', () {
      final p = parseHtmlPreview('<title>${'a' * 400}</title>',
          baseUrl: Uri.parse('https://x.example'))!;
      expect(p.title!.length, 300);
    });

    test('oembedEndpoint only for YouTube and TikTok', () {
      expect(oembedEndpoint('https://youtu.be/x', WallSource.youtube)!.host,
          'www.youtube.com');
      expect(oembedEndpoint('https://www.tiktok.com/@a/video/1', WallSource.tiktok)!.host,
          'www.tiktok.com');
      expect(oembedEndpoint('https://example.com', WallSource.article), isNull);
    });
  });

  group('fetch', () {
    test('uses oEmbed for YouTube', () async {
      final seen = <Uri>[];
      final svc = LinkPreviewService(client: MockClient((req) async {
        seen.add(req.url);
        return _resp(jsonEncode({'title': 'Vid', 'thumbnail_url': 'https://i/t.jpg'}),
            type: 'application/json');
      }));
      final p = await svc.fetch('https://youtu.be/abc');
      expect(p!.title, 'Vid');
      expect(seen.single.path, '/oembed');
    });

    test('falls back to the page when oEmbed fails', () async {
      final svc = LinkPreviewService(client: MockClient((req) async {
        if (req.url.path == '/oembed') return _resp('', status: 404);
        return _resp('<meta property="og:title" content="From page">');
      }));
      expect((await svc.fetch('https://www.youtube.com/watch?v=1'))!.title, 'From page');
    });

    test('non-HTML returns null', () async {
      final svc = LinkPreviewService(client: MockClient((_) async =>
          _resp('%PDF-1.7', type: 'application/pdf')));
      expect(await svc.fetch('https://example.com/file.pdf'), isNull);
    });

    test('non-200 returns null', () async {
      final svc = LinkPreviewService(client: MockClient((_) async => _resp('x', status: 500)));
      expect(await svc.fetch('https://example.com'), isNull);
    });

    test('times out to null', () async {
      final svc = LinkPreviewService(
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return _resp('<title>late</title>');
        }),
      );
      expect(await svc.fetch('https://example.com'), isNull);
    });

    test('rejects non-http schemes without a request', () async {
      var called = false;
      final svc = LinkPreviewService(client: MockClient((_) async {
        called = true;
        return _resp('');
      }));
      expect(await svc.fetch('file:///etc/passwd'), isNull);
      expect(called, isFalse);
    });

    test('only reads the first maxBytes of a huge page', () async {
      final huge = '<title>Big</title>${'x' * (LinkPreviewService.maxBytes * 2)}';
      final svc = LinkPreviewService(client: MockClient((_) async => _resp(huge)));
      expect((await svc.fetch('https://example.com'))!.title, 'Big');
    });
  });
}
