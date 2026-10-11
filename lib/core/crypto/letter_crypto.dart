// lib/core/crypto/letter_crypto.dart
//
// AES-256-GCM encryption for future-letter bodies.
//
// A future letter is written now and opened years from now, which rules out
// the Signal Double Ratchet used for chat: the ratchet advances continuously
// and deliberately destroys old key material, so a message sealed today would
// be undecryptable long before its unlock date. Letters therefore use one
// long-lived key per couple, held only on the two devices.
//
// This is the second of two independent layers. The first is server-side: the
// RLS policy in `20260807000004_future_letters_seal.sql` withholds the
// ciphertext entirely until `unlock_at`. The split matters — the key reaches
// the recipient's device when the letter is written, but the ciphertext does
// not arrive until the day it opens, so possession of either one alone opens
// nothing.
//
// DURABILITY LIMIT, deliberate and worth stating plainly: the key lives in
// device secure storage and is never escrowed to the server. If both spouses
// lose their devices between writing a letter and its unlock date, that letter
// is unreadable by anyone, permanently. `LetterKeyService.requestRedelivery`
// exists so the far more common single-device loss is recoverable from the
// spouse's copy.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'secure_store.dart';

final _algorithm = AesGcm.with256bits();

/// A sealed letter body: GCM ciphertext with its 16-byte tag appended, plus
/// the nonce it was sealed under.
///
/// The nonce is stored alongside the ciphertext (it is not secret); the key is
/// not, and never touches the row.
class SealedLetter {
  const SealedLetter({required this.nonce, required this.ciphertext});

  final Uint8List nonce;
  final Uint8List ciphertext;

  /// Wire form written to `future_letters.body_ciphertext`: the 12-byte nonce
  /// followed by the ciphertext, so one column carries both and they can never
  /// be separated in storage.
  Uint8List toBytes() {
    final out = Uint8List(nonce.length + ciphertext.length)
      ..setAll(0, nonce)
      ..setAll(nonce.length, ciphertext);
    return out;
  }

  /// Parses [bytes] written by [toBytes]. Throws [FormatException] when the
  /// blob is too short to contain a nonce and a GCM tag, rather than returning
  /// something that would fail confusingly later.
  factory SealedLetter.fromBytes(Uint8List bytes) {
    const nonceLength = 12;
    const tagLength = 16;
    if (bytes.length < nonceLength + tagLength) {
      throw const FormatException('letter ciphertext is truncated');
    }
    return SealedLetter(
      nonce: Uint8List.sublistView(bytes, 0, nonceLength),
      ciphertext: Uint8List.sublistView(bytes, nonceLength),
    );
  }
}

/// Generates a couple's long-lived 32-byte letter key.
Future<Uint8List> generateLetterKey() async {
  final key = await _algorithm.newSecretKey();
  return Uint8List.fromList(await key.extractBytes());
}

/// Seals [body] under [key] with a fresh random nonce.
///
/// A new nonce per letter is required, not merely preferred: reusing a nonce
/// under the same key breaks GCM catastrophically, leaking the XOR of the two
/// plaintexts and the authentication subkey. Since one key covers every letter
/// a couple ever writes, the nonce is the only thing keeping them distinct.
Future<SealedLetter> sealLetter({
  required String body,
  required Uint8List key,
}) async {
  final nonce = _algorithm.newNonce();
  final box = await _algorithm.encrypt(
    utf8.encode(body),
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  final cipher = box.cipherText;
  final mac = box.mac.bytes;
  final combined = Uint8List(cipher.length + mac.length)
    ..setAll(0, cipher)
    ..setAll(cipher.length, mac);
  return SealedLetter(
    nonce: Uint8List.fromList(nonce),
    ciphertext: combined,
  );
}

/// Opens a sealed letter.
///
/// Throws [SecretBoxAuthenticationError] when the ciphertext has been altered
/// or the wrong key is supplied — GCM authenticates, so a tampered letter
/// fails loudly instead of decrypting to plausible nonsense.
Future<String> openLetter({
  required SealedLetter sealed,
  required Uint8List key,
}) async {
  const tagLength = 16;
  final bytes = sealed.ciphertext;
  final cipher = Uint8List.sublistView(bytes, 0, bytes.length - tagLength);
  final mac = Uint8List.sublistView(bytes, bytes.length - tagLength);
  final clear = await _algorithm.decrypt(
    SecretBox(cipher, nonce: sealed.nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
  );
  return utf8.decode(clear);
}

/// Stores and retrieves the couple's letter key on this device.
///
/// Keyed by couple id so re-pairing starts a clean key rather than silently
/// carrying the previous relationship's letters forward.
class LetterKeyService {
  LetterKeyService(this._store);

  final SecureStore _store;

  static String storageKey(String coupleId) => 'letter_key:$coupleId';

  Future<Uint8List?> read(String coupleId) async {
    final encoded = await _store.read(storageKey(coupleId));
    if (encoded == null) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      // A corrupt entry is worse than none: it would fail every decrypt with a
      // confusing authentication error. Drop it and let the caller re-derive.
      await _store.delete(storageKey(coupleId));
      return null;
    }
  }

  Future<void> write(String coupleId, Uint8List key) =>
      _store.write(storageKey(coupleId), base64Encode(key));

  /// Returns this device's key, generating one if the couple has none yet.
  ///
  /// Generation is deliberately NOT idempotent across devices: if both spouses
  /// generate independently they end up with different keys and cannot read
  /// each other's letters. The caller must distribute the key to the spouse
  /// (over the Signal session) whenever [existed] comes back false.
  Future<({Uint8List key, bool existed})> ensure(String coupleId) async {
    final existing = await read(coupleId);
    if (existing != null) return (key: existing, existed: true);
    final fresh = await generateLetterKey();
    await write(coupleId, fresh);
    return (key: fresh, existed: false);
  }

  Future<void> clear(String coupleId) => _store.delete(storageKey(coupleId));
}
