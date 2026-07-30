// lib/core/crypto/attachment_crypto.dart
//
// AES-256-GCM encryption for chat attachment bytes (photos/videos). This is a
// SEPARATE key from the Signal session: a fresh random key+nonce is generated
// per attachment, used only to encrypt that one attachment's bytes before
// upload to Supabase Storage. The key/nonce travel only inside the
// Signal-encrypted AttachmentPayload pointer (see chat_payload.dart) -- never
// alongside the ciphertext in Storage -- so Storage holds only opaque bytes
// it can never decrypt.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

final _algorithm = AesGcm.with256bits();

/// One attachment's random key/nonce plus its encrypted bytes. [ciphertext]
/// is the GCM ciphertext with the 16-byte authentication tag appended, ready
/// to upload as-is.
class EncryptedAttachment {
  const EncryptedAttachment({
    required this.key,
    required this.nonce,
    required this.ciphertext,
  });

  /// 32 raw bytes (AES-256).
  final Uint8List key;

  /// 12 raw bytes (GCM nonce).
  final Uint8List nonce;

  final Uint8List ciphertext;
}

/// Encrypts [plaintext] under a freshly generated random key and nonce.
Future<EncryptedAttachment> encryptAttachment(Uint8List plaintext) async {
  final secretKey = await _algorithm.newSecretKey();
  final nonce = _algorithm.newNonce();
  final box = await _algorithm.encrypt(plaintext, secretKey: secretKey, nonce: nonce);
  final keyBytes = Uint8List.fromList(await secretKey.extractBytes());
  return EncryptedAttachment(
    key: keyBytes,
    nonce: Uint8List.fromList(nonce),
    ciphertext: Uint8List.fromList([...box.cipherText, ...box.mac.bytes]),
  );
}

/// Decrypts [ciphertext] (as produced by [encryptAttachment]) using [key] and
/// [nonce]. Throws [SecretBoxAuthenticationError] if the ciphertext was
/// tampered with, or if [key]/[nonce] don't match what encrypted it.
Future<Uint8List> decryptAttachment({
  required Uint8List ciphertext,
  required Uint8List key,
  required Uint8List nonce,
}) async {
  const macLength = 16;
  final cipherBytes = ciphertext.sublist(0, ciphertext.length - macLength);
  final macBytes = ciphertext.sublist(ciphertext.length - macLength);
  final box = SecretBox(cipherBytes, nonce: nonce, mac: Mac(macBytes));
  final clear = await _algorithm.decrypt(box, secretKey: SecretKey(key));
  return Uint8List.fromList(clear);
}
