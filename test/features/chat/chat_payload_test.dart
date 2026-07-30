import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/domain/chat_payload.dart';

void main() {
  test('text round-trips, including reply', () {
    for (final p in [
      const TextPayload(body: 'salam'),
      const TextPayload(body: 're', replyToMessageId: 'm1'),
    ]) {
      final decoded = decodePayload(encodePayload(p));
      expect(decoded, isA<TextPayload>());
      final t = decoded as TextPayload;
      expect(t.body, p.body);
      expect(t.replyToMessageId, p.replyToMessageId);
    }
  });

  test('reaction round-trips add and remove', () {
    for (final add in [true, false]) {
      final p = ReactionPayload(targetMessageId: 'm9', emoji: '❤️', add: add);
      final decoded = decodePayload(encodePayload(p)) as ReactionPayload;
      expect(decoded.targetMessageId, 'm9');
      expect(decoded.emoji, '❤️');
      expect(decoded.add, add);
    }
  });

  test('attachment round-trips a photo, including optional fields', () {
    final p = AttachmentPayload(
      kind: AttachmentKind.photo,
      mimeType: 'image/jpeg',
      sizeBytes: 123456,
      width: 1600,
      height: 1200,
      storageKey: 'couple-1/msg-1',
      encKey: Uint8List.fromList(List.filled(32, 7)),
      nonce: Uint8List.fromList(List.filled(12, 3)),
      thumbnailBytes: Uint8List.fromList([1, 2, 3, 4, 5]),
      caption: 'MashaAllah',
      replyToMessageId: 'm0',
    );
    final decoded = decodePayload(encodePayload(p)) as AttachmentPayload;

    expect(decoded.kind, AttachmentKind.photo);
    expect(decoded.mimeType, 'image/jpeg');
    expect(decoded.sizeBytes, 123456);
    expect(decoded.width, 1600);
    expect(decoded.height, 1200);
    expect(decoded.durationMs, isNull);
    expect(decoded.storageKey, 'couple-1/msg-1');
    expect(decoded.encKey, Uint8List.fromList(List.filled(32, 7)));
    expect(decoded.nonce, Uint8List.fromList(List.filled(12, 3)));
    expect(decoded.thumbnailBytes, Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(decoded.caption, 'MashaAllah');
    expect(decoded.replyToMessageId, 'm0');
  });

  test('attachment round-trips a video with durationMs and no caption/reply', () {
    final p = AttachmentPayload(
      kind: AttachmentKind.video,
      mimeType: 'video/mp4',
      sizeBytes: 999,
      durationMs: 45000,
      storageKey: 'couple-1/msg-2',
      encKey: Uint8List.fromList(List.filled(32, 1)),
      nonce: Uint8List.fromList(List.filled(12, 2)),
      thumbnailBytes: Uint8List.fromList([9, 8, 7]),
    );
    final decoded = decodePayload(encodePayload(p)) as AttachmentPayload;

    expect(decoded.kind, AttachmentKind.video);
    expect(decoded.durationMs, 45000);
    expect(decoded.width, isNull);
    expect(decoded.height, isNull);
    expect(decoded.caption, isNull);
    expect(decoded.replyToMessageId, isNull);
  });

  test('attachment with malformed mediaKind never throws and returns UnsupportedPayload', () {
    final bytes = Uint8ListFromString(
      '{"v":1,"kind":"attachment","mediaKind":"hologram","mime":"x","size":1,'
      '"storage":"s","key":"AAAA","nonce":"AAAA","thumb":"AAAA"}',
    );
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('attachment with numeric mime never throws and returns UnsupportedPayload', () {
    final bytes = Uint8ListFromString(
      '{"v":1,"kind":"attachment","mediaKind":"photo","mime":123,"size":1,'
      '"storage":"s","key":"AAAA","nonce":"AAAA","thumb":"AAAA"}',
    );
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('attachment with non-base64 key never throws and returns UnsupportedPayload', () {
    final bytes = Uint8ListFromString(
      '{"v":1,"kind":"attachment","mediaKind":"photo","mime":"image/jpeg","size":1,'
      '"storage":"s","key":"not-valid-base64!!","nonce":"AAAA","thumb":"AAAA"}',
    );
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('unknown kind or newer version decodes to UnsupportedPayload', () {
    final future = '{"v":99,"kind":"hologram"}';
    final bytes = Uint8ListFromString(future);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('text payload with numeric body never throws and returns UnsupportedPayload',
      () {
    final bytes = Uint8ListFromString('{"v":1,"kind":"text","body":123}');
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test(
      'text payload with numeric reply never throws and returns UnsupportedPayload',
      () {
    final bytes =
        Uint8ListFromString('{"v":1,"kind":"text","body":"hello","reply":123}');
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test(
      'reaction with numeric target never throws and returns UnsupportedPayload',
      () {
    final bytes = Uint8ListFromString(
        '{"v":1,"kind":"reaction","target":123,"emoji":"❤️","op":"add"}');
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test(
      'reaction with numeric emoji never throws and returns UnsupportedPayload',
      () {
    final bytes = Uint8ListFromString(
        '{"v":1,"kind":"reaction","target":"m1","emoji":456,"op":"add"}');
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test('random non-JSON bytes never throws and returns UnsupportedPayload', () {
    final bytes = Uint8List.fromList([0xFF, 0xFE, 0xFD, 0xFC]);
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });

  test(
      'text payload with string version never throws and returns UnsupportedPayload',
      () {
    final bytes = Uint8ListFromString('{"v":"1","kind":"text","body":"hi"}');
    expect(() => decodePayload(bytes), returnsNormally);
    expect(decodePayload(bytes), isA<UnsupportedPayload>());
  });
}

Uint8List Uint8ListFromString(String s) => Uint8List.fromList(utf8.encode(s));
