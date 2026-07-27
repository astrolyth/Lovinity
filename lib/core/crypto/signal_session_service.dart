// lib/core/crypto/signal_session_service.dart
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../errors/failures.dart';
import '../storage/signal_db.dart';
import 'key_vault.dart';
import 'prekey_bundle_source.dart';
import 'stores/drift_signal_store.dart';

/// One encrypted copy of a message, addressed to a single device.
class EncryptedCopy {
  const EncryptedCopy({
    required this.userId,
    required this.deviceNum,
    required this.ciphertext,
    required this.cipherType,
  });

  final String userId;
  final int deviceNum;
  final Uint8List ciphertext;

  /// [CiphertextMessage.prekeyType] (3) for the first message to a device,
  /// [CiphertextMessage.whisperType] (2) afterwards.
  final int cipherType;
}

/// The only crypto API the rest of the app uses. Nothing above this layer
/// should import libsignal.
class SignalSessionService {
  SignalSessionService({
    required SignalDb db,
    required KeyVault vault,
    required this._bundles,
    required this._selfUserId,
    required this._selfDeviceNum,
  })  : _store = DriftSignalStore(db, vault);

  final DriftSignalStore _store;
  final PreKeyBundleSource _bundles;
  final String _selfUserId;
  final int _selfDeviceNum;

  /// Encrypt one copy per recipient device, plus per this user's OTHER devices
  /// so sent messages appear there too.
  Future<List<EncryptedCopy>> encryptFor({
    required String recipientUserId,
    required Uint8List plaintext,
  }) async {
    final targets = <({String userId, int deviceNum})>[];

    // Roster lookups consume nothing; only a real handshake consumes a prekey.
    if (recipientUserId != _selfUserId) {
      final recipientDevices = await _bundles.deviceNumsFor(recipientUserId);
      if (recipientDevices.isEmpty) {
        // The recipient has no registered device yet. Encrypting to nobody
        // would produce zero copies and a message the recipient can never
        // receive; fail loudly so the caller marks it failed (retryable)
        // rather than showing a false "sent".
        throw UnknownFailure(
            'Recipient $recipientUserId has no registered device yet');
      }
      for (final n in recipientDevices) {
        targets.add((userId: recipientUserId, deviceNum: n));
      }
    }
    for (final n in await _bundles.deviceNumsFor(_selfUserId)) {
      if (n == _selfDeviceNum) continue;
      targets.add((userId: _selfUserId, deviceNum: n));
    }

    final copies = <EncryptedCopy>[];
    for (final t in targets) {
      final address = SignalProtocolAddress(t.userId, t.deviceNum);
      await _ensureSession(address);
      final cipher = SessionCipher.fromStore(_store, address);
      final message = await cipher.encrypt(plaintext);
      copies.add(EncryptedCopy(
        userId: t.userId,
        deviceNum: t.deviceNum,
        ciphertext: Uint8List.fromList(message.serialize()),
        cipherType: message.getType(),
      ));
    }
    return copies;
  }

  Future<Uint8List> decryptFrom({
    required String senderUserId,
    required int senderDeviceNum,
    required Uint8List ciphertext,
    required int cipherType,
  }) async {
    final address = SignalProtocolAddress(senderUserId, senderDeviceNum);
    final cipher = SessionCipher.fromStore(_store, address);

    if (cipherType == CiphertextMessage.prekeyType) {
      // X3DH: processing this establishes the session on our side.
      return cipher.decrypt(PreKeySignalMessage(ciphertext));
    }
    return cipher.decryptFromSignal(SignalMessage.fromSerialized(ciphertext));
  }

  /// X3DH only when we have no session for this address yet. This is the ONLY
  /// place allowed to fetch a bundle, because fetching consumes a one-time
  /// prekey server-side.
  Future<void> _ensureSession(SignalProtocolAddress address) async {
    if (await _store.containsSession(address)) return;

    final bundle =
        await _bundles.bundleFor(address.getName(), address.getDeviceId());
    if (bundle == null) {
      throw UnknownFailure(
          'No device bundle available for ${address.getName()} device ${address.getDeviceId()}');
    }
    final builder = SessionBuilder.fromSignalStore(_store, address);
    await builder.processPreKeyBundle(bundle.toPreKeyBundle());
  }
}
