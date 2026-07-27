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
