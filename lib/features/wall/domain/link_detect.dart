import 'wall_models.dart';

final _urlRe = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
const _trailing = '.,!?;:"\')]}>…';

/// The first http(s) URL in [text], with trailing punctuation trimmed.
/// A closing paren is kept when the URL also contains a matching "(".
String? extractFirstUrl(String text) {
  final match = _urlRe.firstMatch(text);
  if (match == null) return null;
  var url = match.group(0)!;
  while (url.isNotEmpty && _trailing.contains(url[url.length - 1])) {
    if (url.endsWith(')') &&
        '('.allMatches(url).length >= ')'.allMatches(url).length) {
      break;
    }
    url = url.substring(0, url.length - 1);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return url;
}

/// Source for a URL, from its host (subdomains included).
WallSource classifyUrl(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  bool on(String domain) => host == domain || host.endsWith('.$domain');
  if (on('youtube.com') || on('youtu.be')) return WallSource.youtube;
  if (on('instagram.com')) return WallSource.instagram;
  if (on('tiktok.com')) return WallSource.tiktok;
  return WallSource.article;
}

/// Splits text shared into the app: a link if there is one (the rest is
/// dropped — apps prepend titles/marketing copy), otherwise a note capped at
/// 1000 characters.
({String? url, String? note}) parseSharedText(String text) {
  final url = extractFirstUrl(text);
  if (url != null) return (url: url, note: null);
  final note = text.trim();
  if (note.isEmpty) return (url: null, note: null);
  return (url: null, note: note.length > 1000 ? note.substring(0, 1000) : note);
}
