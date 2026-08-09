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

enum AttachmentKind { photo, video }

class AttachmentPayload extends ChatPayload {
  const AttachmentPayload({
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    required this.storageKey,
    required this.encKey,
    required this.nonce,
    required this.thumbnailBytes,
    this.caption,
    this.replyToMessageId,
  });

  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  /// Path in the `chat-media` Storage bucket: `<couple_id>/<message_id>`.
  final String storageKey;

  /// 32-byte AES-256 key, random per attachment. Travels ONLY inside this
  /// Signal-encrypted pointer -- never alongside the ciphertext in Storage.
  final Uint8List encKey;

  /// 12-byte GCM nonce.
  final Uint8List nonce;

  /// Small JPEG, embedded inline so a preview renders with zero Storage
  /// round-trip.
  final Uint8List thumbnailBytes;
  final String? caption;
  final String? replyToMessageId;
}

/// Carries the couple's long-lived future-letter key to the spouse's device.
///
/// Same shape as [AttachmentPayload]: a Signal-encrypted pointer carrying an
/// AES key whose ciphertext lives elsewhere — here in `future_letters`, not
/// Storage. The letter key cannot ride the Double Ratchet itself, because the
/// ratchet destroys old key material and a letter must stay readable for years
/// (see `lib/core/crypto/letter_crypto.dart`).
///
/// This is a control message, not conversation: it must never be rendered in
/// the chat thread.
class LetterKeyPayload extends ChatPayload {
  const LetterKeyPayload({required this.coupleId, required this.letterKey});

  final String coupleId;

  /// 32-byte AES-256 key. Travels only inside this Signal-encrypted envelope.
  final Uint8List letterKey;
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
    AttachmentPayload() => {
        'v': _payloadVersion,
        'kind': 'attachment',
        'mediaKind': p.kind.name,
        'mime': p.mimeType,
        'size': p.sizeBytes,
        if (p.width != null) 'w': p.width,
        if (p.height != null) 'h': p.height,
        if (p.durationMs != null) 'dur': p.durationMs,
        'storage': p.storageKey,
        'key': base64Encode(p.encKey),
        'nonce': base64Encode(p.nonce),
        'thumb': base64Encode(p.thumbnailBytes),
        if (p.caption != null) 'caption': p.caption,
        if (p.replyToMessageId != null) 'reply': p.replyToMessageId,
      },
    LetterKeyPayload() => {
        'v': _payloadVersion,
        'kind': 'letterKey',
        'couple': p.coupleId,
        'key': base64Encode(p.letterKey),
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
      'attachment'
          when m['mediaKind'] is String &&
              (m['mediaKind'] == 'photo' || m['mediaKind'] == 'video') &&
              m['mime'] is String &&
              m['size'] is num &&
              m['storage'] is String &&
              m['key'] is String &&
              m['nonce'] is String &&
              m['thumb'] is String &&
              (m['w'] == null || m['w'] is num) &&
              (m['h'] == null || m['h'] is num) &&
              (m['dur'] == null || m['dur'] is num) &&
              (m['caption'] == null || m['caption'] is String) &&
              (m['reply'] == null || m['reply'] is String) =>
        AttachmentPayload(
          kind: m['mediaKind'] == 'video' ? AttachmentKind.video : AttachmentKind.photo,
          mimeType: m['mime'] as String,
          sizeBytes: (m['size'] as num).toInt(),
          width: (m['w'] as num?)?.toInt(),
          height: (m['h'] as num?)?.toInt(),
          durationMs: (m['dur'] as num?)?.toInt(),
          storageKey: m['storage'] as String,
          encKey: base64Decode(m['key'] as String),
          nonce: base64Decode(m['nonce'] as String),
          thumbnailBytes: base64Decode(m['thumb'] as String),
          caption: m['caption'] as String?,
          replyToMessageId: m['reply'] as String?,
        ),
      'letterKey' when m['couple'] is String && m['key'] is String =>
        LetterKeyPayload(
          coupleId: m['couple'] as String,
          letterKey: base64Decode(m['key'] as String),
        ),
      _ => const UnsupportedPayload(),
    };
  } catch (_) {
    return const UnsupportedPayload();
  }
}
