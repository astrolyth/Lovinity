import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../theme/theme_provider.dart';
import 'app_lock.dart';

const _secretKey = 'faceid_login';
const _markerKey = 'faceid_email';

/// "Sign in with Face ID": after a password sign-in the user can opt to keep
/// their email + password on this phone, released only to Face ID.
///
/// Supabase revokes the session on sign-out, so a saved session can't be
/// revived; the credentials are what make a later Face ID sign-in possible.
/// On iOS the Keychain item itself requires the currently enrolled Face ID
/// (`biometryCurrentSet`: re-enrolling a face invalidates it) and never
/// leaves this device. Android's store is Keystore-encrypted and the read is
/// gated by a biometric prompt in the app.
///
/// shortcut: Android gates the read in-app, not in the Keystore item itself;
/// move to a biometric-bound Keystore key if that becomes a requirement.
class FaceIdLogin {
  FaceIdLogin(this._ref);
  final Ref _ref;

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.passcode,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );

  /// The email whose credentials are saved, without touching the secret
  /// (reading the secret on iOS shows Face ID).
  String? get savedEmail =>
      _ref.read(sharedPreferencesProvider)?.getString(_markerKey);

  Future<bool> deviceSupports() async {
    final auth = LocalAuthentication();
    try {
      return await auth.isDeviceSupported() && await auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(String email, String password) async {
    await _storage.write(
      key: _secretKey,
      value: jsonEncode({'email': email, 'password': password}),
    );
    await _ref.read(sharedPreferencesProvider)?.setString(_markerKey, email);
  }

  /// The saved credentials after Face ID succeeds, else null.
  Future<(String, String)?> read() async {
    if (Platform.isAndroid &&
        !await unlockWithBiometrics('Sign in to Lovinity')) {
      return null;
    }
    try {
      final raw = await _storage.read(key: _secretKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map;
      return (m['email'] as String, m['password'] as String);
    } catch (_) {
      // Cancelled Face ID, or the item was invalidated by a new face.
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _secretKey);
    await _ref.read(sharedPreferencesProvider)?.remove(_markerKey);
  }
}

final faceIdLoginProvider = Provider<FaceIdLogin>(FaceIdLogin.new);
