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

/// A per-attachment AES-256 key (32 bytes) + GCM nonce (12 bytes).
typedef AttachmentKeyMaterial = ({Uint8List key, Uint8List nonce});

/// Generates the random key/nonce for ONE attachment.
///
/// Deliberately separate from [encryptAttachment]: generating key material is
/// cheap and never touches the attachment bytes, so a caller can mint it up
/// front (e.g. to write an optimistic local row immediately) and only pay the
/// expensive `encrypt` cost afterwards. [encryptAttachment] calls this when no
/// material is supplied, so this stays the single source of key/nonce
/// generation.
Future<AttachmentKeyMaterial> generateAttachmentKey() async {
  final secretKey = await _algorithm.newSecretKey();
  return (
    key: Uint8List.fromList(await secretKey.extractBytes()),
    nonce: Uint8List.fromList(_algorithm.newNonce()),
  );
}

/// Encrypts [plaintext] under [keyMaterial], or under a freshly generated
/// random key and nonce when [keyMaterial] is omitted.
Future<EncryptedAttachment> encryptAttachment(
  Uint8List plaintext, {
  AttachmentKeyMaterial? keyMaterial,
}) async {
  final material = keyMaterial ?? await generateAttachmentKey();
  final box = await _algorithm.encrypt(
    plaintext,
    secretKey: SecretKey(material.key),
    nonce: material.nonce,
  );
  // Concatenate ciphertext||mac into a Uint8List WITHOUT an intermediate
  // growable List<int>. A `[...a, ...b]` spread boxes every element (~8 bytes
  // each on a 64-bit VM) before Uint8List.fromList copies it back down, which
  // for an N-byte attachment transiently costs ~8N extra bytes. Videos are
  // never re-encoded/compressed in this app, so N can be 50-200MB and that
  // intermediate alone is enough to get the app OOM-killed.
  final cipherBytes = box.cipherText;
  final macBytes = box.mac.bytes;
  final combined = Uint8List(cipherBytes.length + macBytes.length)
    ..setRange(0, cipherBytes.length, cipherBytes)
    ..setRange(cipherBytes.length, cipherBytes.length + macBytes.length, macBytes);
  return EncryptedAttachment(
    key: material.key,
    nonce: material.nonce,
    ciphertext: combined,
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
