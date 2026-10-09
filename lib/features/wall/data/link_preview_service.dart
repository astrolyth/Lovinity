import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../domain/link_detect.dart';
import '../domain/wall_models.dart';

@immutable
class LinkPreview {
  const LinkPreview({this.title, this.description, this.imageUrl, this.siteName});

  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
}

/// Fetches link previews ON THE DEVICE (never via our server), so there is
/// no server-side "fetch any URL" surface. Never throws: any failure,
/// non-HTML response or timeout yields null and the item posts without one.
class LinkPreviewService {
  LinkPreviewService({http.Client? client, this.timeout = const Duration(seconds: 5)})
      : _client = client ?? http.Client();

  static const maxBytes = 512 * 1024;
  static const _userAgent = 'Mozilla/5.0 (compatible; LovinityLinkPreview/1.0)';

  final http.Client _client;
  final Duration timeout;

  Future<LinkPreview?> fetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    try {
      return await _fetch(url, uri).timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    }
  }

  Future<LinkPreview?> _fetch(String url, Uri uri) async {
    final oembed = oembedEndpoint(url, classifyUrl(url));
    if (oembed != null) {
      try {
        final res = await _client.get(oembed, headers: {'User-Agent': _userAgent});
        if (res.statusCode == 200) {
          final p = parseOEmbed(utf8.decode(res.bodyBytes, allowMalformed: true));
          if (p != null) return p;
        }
      } catch (_) {
        // fall through to the page itself
      }
    }

    final req = http.Request('GET', uri)
      ..headers['User-Agent'] = _userAgent
      ..headers['Accept'] = 'text/html,application/xhtml+xml';
    final res = await _client.send(req);
    if (res.statusCode != 200) return null;
    final type = res.headers['content-type'] ?? '';
    if (!type.contains('html')) return null;

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      bytes.add(chunk);
      if (bytes.length >= maxBytes) break; // cancels the rest of the body
    }
    final html = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    return parseHtmlPreview(html, baseUrl: res.request?.url ?? uri);
  }

  void close() => _client.close();
}

/// Public oEmbed endpoints that work without an API key.
Uri? oembedEndpoint(String url, WallSource source) => switch (source) {
      WallSource.youtube =>
        Uri.https('www.youtube.com', '/oembed', {'url': url, 'format': 'json'}),
      WallSource.tiktok => Uri.https('www.tiktok.com', '/oembed', {'url': url}),
      _ => null,
    };

LinkPreview? parseOEmbed(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final title = _clean(json['title'] as String?, 300);
    final image = _httpUrl(json['thumbnail_url'] as String?, null);
    if (title == null && image == null) return null;
    return LinkPreview(
      title: title,
      imageUrl: image,
      siteName: _clean(json['provider_name'] as String?, 100),
    );
  } catch (_) {
    return null;
  }
}

LinkPreview? parseHtmlPreview(String html, {required Uri baseUrl}) {
  final doc = html_parser.parse(html);
  String? meta(String key) {
    for (final m in doc.querySelectorAll('meta')) {
      final k = m.attributes['property'] ?? m.attributes['name'];
      if (k != null && k.toLowerCase() == key) {
        final v = m.attributes['content']?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return null;
  }

  final title = _clean(
      meta('og:title') ?? meta('twitter:title') ?? doc.querySelector('title')?.text,
      300);
  final description = _clean(
      meta('og:description') ?? meta('twitter:description') ?? meta('description'),
      1000);
  final image = _httpUrl(
      meta('og:image') ?? meta('og:image:url') ?? meta('twitter:image'), baseUrl);
  final site = _clean(meta('og:site_name'), 100);

  if (title == null && image == null && description == null) return null;
  return LinkPreview(
      title: title, description: description, imageUrl: image, siteName: site);
}

String? _clean(String? s, int max) {
  if (s == null) return null;
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;
  return t.length > max ? t.substring(0, max) : t;
}

String? _httpUrl(String? raw, Uri? base) {
  if (raw == null || raw.trim().isEmpty) return null;
  final resolved = base == null ? Uri.tryParse(raw.trim()) : base.resolve(raw.trim());
  if (resolved == null) return null;
  if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
  final s = resolved.toString();
  return s.length > 2048 ? null : s;
}
