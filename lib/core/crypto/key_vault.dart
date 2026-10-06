import 'dart:convert';
import 'dart:typed_data';

import 'secure_store.dart';
import 'signal_keys.dart';

/// Persists Signal private material in platform secure storage (Keychain / Keystore).
///
/// [scope] namespaces every key (in practice: the signed-in user id), so
/// several accounts can share one device without reading or overwriting each
/// other's identity and device number. Unscoped (null) is for tests only.
class KeyVault {
  KeyVault(this._storage, {String? scope}) : _prefix = scope == null ? '' : '$scope/';

  final SecureStore _storage;
  final String _prefix;

  String _k(String key) => '$_prefix$key';

  static const _identityKey = 'signal.identity.priv';
  static const _spkKey = 'signal.spk.priv';
  static const _otpkPrefix = 'signal.otpk.';
  static const _deviceIdKey = 'signal.device_id';
  static const _registrationIdKey = 'signal_registration_id';
  static const _deviceNumKey = 'signal_device_num';

  Future<bool> hasIdentity() async {
    final v = await _storage.read(_k(_identityKey));
    return v != null && v.isNotEmpty;
  }

  Future<String?> deviceId() => _storage.read(_k(_deviceIdKey));

  Future<void> saveDeviceId(String id) =>
      _storage.write(_k(_deviceIdKey), id);

  Future<void> savePrivate(PrivateBundle bundle) async {
    await _storage.write(
      _k(_identityKey),
      base64Encode(bundle.identitySerialized),
    );
    await _storage.write(
      _k(_spkKey),
      base64Encode(bundle.signedPrekeySerialized),
    );
    for (final entry in bundle.oneTimePrekeysSerialized.entries) {
      await _storage.write(
        _k('$_otpkPrefix${entry.key}'),
        base64Encode(entry.value),
      );
    }
    await _storage.write(
      _k(_registrationIdKey),
      '${bundle.registrationId}',
    );
  }

  Future<Uint8List?> readIdentity() async {
    final v = await _storage.read(_k(_identityKey));
    if (v == null) return null;
    return Uint8List.fromList(base64Decode(v));
  }

  Future<int?> readRegistrationId() async {
    final v = await _storage.read(_k(_registrationIdKey));
    return v == null ? null : int.tryParse(v);
  }

  Future<void> saveDeviceNum(int num) =>
      _storage.write(_k(_deviceNumKey), '$num');

  Future<int?> readDeviceNum() async {
    final v = await _storage.read(_k(_deviceNumKey));
    return v == null ? null : int.tryParse(v);
  }

  Future<void> clearDeviceNum() => _storage.delete(_k(_deviceNumKey));
}
