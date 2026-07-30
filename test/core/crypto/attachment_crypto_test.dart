import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/attachment_crypto.dart';

void main() {
  test('encryptAttachment/decryptAttachment round-trips arbitrary bytes', () async {
    final plaintext = Uint8List.fromList(List.generate(5000, (i) => i % 256));
    final enc = await encryptAttachment(plaintext);

    expect(enc.key, hasLength(32));
    expect(enc.nonce, hasLength(12));

    final decrypted = await decryptAttachment(
      ciphertext: enc.ciphertext,
      key: enc.key,
      nonce: enc.nonce,
    );
    expect(decrypted, plaintext);
  });

  test('two encryptions of the same plaintext use different keys, nonces, and ciphertext',
      () async {
    final plaintext = Uint8List.fromList([1, 2, 3, 4]);
    final a = await encryptAttachment(plaintext);
    final b = await encryptAttachment(plaintext);

    expect(a.key, isNot(b.key));
    expect(a.nonce, isNot(b.nonce));
    expect(a.ciphertext, isNot(b.ciphertext));
  });

  test('decryptAttachment throws on tampered ciphertext', () async {
    final plaintext = Uint8List.fromList([9, 9, 9]);
    final enc = await encryptAttachment(plaintext);
    final tampered = Uint8List.fromList(enc.ciphertext);
    tampered[0] ^= 0xFF;

    await expectLater(
      decryptAttachment(ciphertext: tampered, key: enc.key, nonce: enc.nonce),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('decryptAttachment throws with the wrong key', () async {
    final plaintext = Uint8List.fromList([9, 9, 9]);
    final enc = await encryptAttachment(plaintext);
    final wrongKey = Uint8List.fromList(List.filled(32, 1));

    await expectLater(
      decryptAttachment(ciphertext: enc.ciphertext, key: wrongKey, nonce: enc.nonce),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
