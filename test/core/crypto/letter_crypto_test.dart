import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/letter_crypto.dart';
import 'package:lovinity/core/crypto/secure_store.dart';

void main() {
  group('seal / open', () {
    test('round-trips a letter body', () async {
      final key = await generateLetterKey();
      final sealed = await sealLetter(body: 'See you in Madinah.', key: key);
      expect(await openLetter(sealed: sealed, key: key),
          'See you in Madinah.');
    });

    test('handles unicode and long bodies', () async {
      final key = await generateLetterKey();
      final body = '${'ٱلْحَمْدُ لِلَّٰهِ 🤍 ' * 200}end';
      final sealed = await sealLetter(body: body, key: key);
      expect(await openLetter(sealed: sealed, key: key), body);
    });

    test('a different key cannot open it', () async {
      final key = await generateLetterKey();
      final wrong = await generateLetterKey();
      final sealed = await sealLetter(body: 'private', key: key);
      expect(
        () => openLetter(sealed: sealed, key: wrong),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('tampering is detected rather than decrypting to nonsense', () async {
      final key = await generateLetterKey();
      final sealed = await sealLetter(body: 'private', key: key);
      final corrupted = Uint8List.fromList(sealed.ciphertext);
      corrupted[0] ^= 0xFF;
      expect(
        () => openLetter(
          sealed: SealedLetter(nonce: sealed.nonce, ciphertext: corrupted),
          key: key,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    // One key covers every letter a couple ever writes, so the nonce is the
    // only thing keeping two letters distinct. Nonce reuse under one key breaks
    // GCM catastrophically — it leaks the XOR of the plaintexts.
    test('uses a fresh nonce for every letter', () async {
      final key = await generateLetterKey();
      final nonces = <String>{};
      for (var i = 0; i < 25; i++) {
        final sealed = await sealLetter(body: 'letter $i', key: key);
        nonces.add(sealed.nonce.join(','));
      }
      expect(nonces.length, 25);
    });

    test('identical bodies produce different ciphertexts', () async {
      final key = await generateLetterKey();
      final a = await sealLetter(body: 'same', key: key);
      final b = await sealLetter(body: 'same', key: key);
      expect(a.ciphertext, isNot(equals(b.ciphertext)));
    });
  });

  group('wire format', () {
    test('round-trips through the stored byte form', () async {
      final key = await generateLetterKey();
      final sealed = await sealLetter(body: 'hello', key: key);
      final restored = SealedLetter.fromBytes(sealed.toBytes());
      expect(restored.nonce, sealed.nonce);
      expect(restored.ciphertext, sealed.ciphertext);
      expect(await openLetter(sealed: restored, key: key), 'hello');
    });

    test('rejects a truncated blob loudly', () {
      expect(
        () => SealedLetter.fromBytes(Uint8List(8)),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('LetterKeyService', () {
    test('generates once and reports reuse afterwards', () async {
      final service = LetterKeyService(InMemorySecureStore());
      final first = await service.ensure('couple-1');
      expect(first.existed, isFalse);

      final second = await service.ensure('couple-1');
      expect(second.existed, isTrue,
          reason: 'a second call must not mint a new key');
      expect(second.key, first.key);
    });

    test('keeps keys separate per couple', () async {
      final service = LetterKeyService(InMemorySecureStore());
      final a = await service.ensure('couple-1');
      final b = await service.ensure('couple-2');
      expect(a.key, isNot(equals(b.key)));
    });

    test('read returns null before a key exists', () async {
      final service = LetterKeyService(InMemorySecureStore());
      expect(await service.read('couple-1'), isNull);
    });

    test('clear removes the key so a failed handshake can be retried',
        () async {
      final service = LetterKeyService(InMemorySecureStore());
      final first = await service.ensure('couple-1');
      await service.clear('couple-1');
      expect(await service.read('couple-1'), isNull);

      final second = await service.ensure('couple-1');
      expect(second.existed, isFalse);
      expect(second.key, isNot(equals(first.key)));
    });

    test('drops a corrupt entry instead of failing every decrypt', () async {
      final store = InMemorySecureStore();
      await store.write(LetterKeyService.storageKey('couple-1'), 'not base64!');
      final service = LetterKeyService(store);
      expect(await service.read('couple-1'), isNull);
      // And recovers cleanly afterwards.
      expect((await service.ensure('couple-1')).existed, isFalse);
    });

    test('a written key is readable verbatim', () async {
      final service = LetterKeyService(InMemorySecureStore());
      final key = await generateLetterKey();
      await service.write('couple-1', key);
      expect(await service.read('couple-1'), key);
    });
  });
}
