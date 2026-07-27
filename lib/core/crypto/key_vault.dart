import 'dart:convert';
import 'dart:typed_data';

import 'secure_store.dart';
import 'signal_keys.dart';

/// Persists Signal private material in platform secure storage (Keychain / Keystore).
class KeyVault {
  KeyVault(this._storage);

  final SecureStore _storage;

  static const _identityKey = 'signal.identity.priv';
  static const _spkKey = 'signal.spk.priv';
  static const _otpkPrefix = 'signal.otpk.';
  static const _deviceIdKey = 'signal.device_id';
  static const _registrationIdKey = 'signal_registration_id';
  static const _deviceNumKey = 'signal_device_num';

  Future<bool> hasIdentity() async {
    final v = await _storage.read(_identityKey);
    return v != null && v.isNotEmpty;
  }

  Future<String?> deviceId() => _storage.read(_deviceIdKey);

  Future<void> saveDeviceId(String id) =>
      _storage.write(_deviceIdKey, id);

  Future<void> savePrivate(PrivateBundle bundle) async {
    await _storage.write(
      _identityKey,
      base64Encode(bundle.identitySerialized),
    );
    await _storage.write(
      _spkKey,
      base64Encode(bundle.signedPrekeySerialized),
    );
    for (final entry in bundle.oneTimePrekeysSerialized.entries) {
      await _storage.write(
        '$_otpkPrefix${entry.key}',
        base64Encode(entry.value),
      );
    }
    await _storage.write(
      _registrationIdKey,
      '${bundle.registrationId}',
    );
  }

  Future<Uint8List?> readIdentity() async {
    final v = await _storage.read(_identityKey);
    if (v == null) return null;
    return Uint8List.fromList(base64Decode(v));
  }

  Future<int?> readRegistrationId() async {
    final v = await _storage.read(_registrationIdKey);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> saveDeviceNum(int num) =>
      _storage.write(_deviceNumKey, '$num');

  Future<int?> readDeviceNum() async {
    final v = await _storage.read(_deviceNumKey);
    return v == null ? null : int.tryParse(v);
  }

  Future<void> clearDeviceNum() => _storage.delete(_deviceNumKey);

  Future<void> wipe() async {
    await _storage.deleteAll();
  }
}
