import 'dart:convert';
import 'dart:typed_data';

const int _payloadVersion = 1;

sealed class ChatPayload {
  const ChatPayload();
}

class TextPayload extends ChatPayload {
  const TextPayload({required this.body, this.replyToMessageId});
  final String body;
  final String? replyToMessageId;
}

class ReactionPayload extends ChatPayload {
  const ReactionPayload({
    required this.targetMessageId,
    required this.emoji,
    required this.add,
  });
  final String targetMessageId;
  final String emoji;
  final bool add;
}

/// A payload from a newer/unknown client — skipped, never fatal.
class UnsupportedPayload extends ChatPayload {
  const UnsupportedPayload();
}

Uint8List encodePayload(ChatPayload p) {
  final map = switch (p) {
    TextPayload() => {
        'v': _payloadVersion,
        'kind': 'text',
        'body': p.body,
        if (p.replyToMessageId != null) 'reply': p.replyToMessageId,
      },
    ReactionPayload() => {
        'v': _payloadVersion,
        'kind': 'reaction',
        'target': p.targetMessageId,
        'emoji': p.emoji,
        'op': p.add ? 'add' : 'remove',
      },
    UnsupportedPayload() => {'v': _payloadVersion, 'kind': 'unsupported'},
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

ChatPayload decodePayload(Uint8List bytes) {
  try {
    final Map<String, dynamic> m =
        Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);

    // Guard the version cast: check that v is a num AND matches the version
    final v = m['v'];
    if (v is! num || v != _payloadVersion) return const UnsupportedPayload();

    return switch (m['kind']) {
      'text' when m['body'] is String && (m['reply'] == null || m['reply'] is String) =>
        TextPayload(
          body: m['body'] as String,
          replyToMessageId: m['reply'] is String ? m['reply'] as String : null,
        ),
      'reaction' when m['target'] is String && m['emoji'] is String =>
        ReactionPayload(
          targetMessageId: m['target'] as String,
          emoji: m['emoji'] as String,
          add: m['op'] != 'remove',
        ),
      _ => const UnsupportedPayload(),
    };
  } catch (_) {
    return const UnsupportedPayload();
  }
}
