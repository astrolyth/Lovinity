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

  test('round-trips a large plaintext byte-identically', () async {
    // Regression guard for the ciphertext-assembly fix: the concatenation of
    // GCM ciphertext||mac must not go through a boxed intermediate List<int>
    // (which cost ~8x the attachment size transiently and could OOM-kill the
    // app on an un-recompressed phone video). 2MB is big enough for the
    // fix's shape to matter without making the test slow; this asserts the
    // rewrite didn't change behaviour, not peak memory (not testable here).
    final plaintext = Uint8List(2000000);
    for (var i = 0; i < plaintext.length; i++) {
      plaintext[i] = (i * 31 + 7) & 0xFF;
    }

    final enc = await encryptAttachment(plaintext);
    expect(enc.ciphertext, hasLength(plaintext.length + 16),
        reason: 'ciphertext is the GCM output plus the 16-byte tag');

    final decrypted = await decryptAttachment(
      ciphertext: enc.ciphertext,
      key: enc.key,
      nonce: enc.nonce,
    );
    expect(decrypted.length, plaintext.length);
    expect(decrypted, plaintext);
  });

  test('encryptAttachment reuses supplied key material instead of minting new',
      () async {
    // ChatService generates the key/nonce up front (so the optimistic row can
    // be written before the expensive encrypt) and then hands the SAME
    // material here -- the local row, the uploaded ciphertext and the payload
    // sent to the spouse must all agree.
    final material = await generateAttachmentKey();
    expect(material.key, hasLength(32));
    expect(material.nonce, hasLength(12));

    final plaintext = Uint8List.fromList([7, 7, 7, 42]);
    final enc = await encryptAttachment(plaintext, keyMaterial: material);

    expect(enc.key, material.key);
    expect(enc.nonce, material.nonce);
    final decrypted = await decryptAttachment(
      ciphertext: enc.ciphertext,
      key: material.key,
      nonce: material.nonce,
    );
    expect(decrypted, plaintext);
  });

  test('generateAttachmentKey returns fresh material on every call', () async {
    final a = await generateAttachmentKey();
    final b = await generateAttachmentKey();
    expect(a.key, isNot(b.key));
    expect(a.nonce, isNot(b.nonce));
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
