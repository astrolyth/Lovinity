// test/core/crypto/prekey_bundle_source_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:lovinity/core/crypto/prekey_bundle_source.dart';

void main() {
  test('DeviceBundle converts to a libsignal PreKeyBundle', () {
    final identity = generateIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 7);
    final otp = generatePreKeys(1, 1).first;

    final b = DeviceBundle(
      deviceNum: 2,
      registrationId: 1234,
      identityPub: identity.getPublicKey().serialize(),
      signedPrekeyId: 7,
      signedPrekeyPub: signed.getKeyPair().publicKey.serialize(),
      signedPrekeySig: signed.signature,
      oneTimePrekeyId: otp.id,
      oneTimePrekeyPub: otp.getKeyPair().publicKey.serialize(),
    );

    final bundle = b.toPreKeyBundle();
    expect(bundle.getDeviceId(), 2);
    expect(bundle.getSignedPreKeyId(), 7);
    expect(bundle.getPreKeyId(), otp.id);
  });

  test('DeviceBundle without a one-time prekey still converts (exhausted)', () {
    final identity = generateIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 1);

    final b = DeviceBundle(
      deviceNum: 1,
      registrationId: 9,
      identityPub: identity.getPublicKey().serialize(),
      signedPrekeyId: 1,
      signedPrekeyPub: signed.getKeyPair().publicKey.serialize(),
      signedPrekeySig: signed.signature,
      oneTimePrekeyId: null,
      oneTimePrekeyPub: null,
    );

    final bundle = b.toPreKeyBundle();
    expect(bundle.getPreKeyId(), isNull);
    expect(bundle.getPreKey(), isNull);
  });

  test('DeviceBundle.fromRow decodes hex-string bytea with \\x prefix', () {
    // PostgREST returns bytea as \x-prefixed hex strings
    final row = <String, dynamic>{
      'device_num': 2,
      'registration_id': 1234,
      'identity_pub': r'\x0501020304',
      'signed_prekey_id': 7,
      'signed_prekey_pub': r'\xaabbccdd',
      'signed_prekey_sig': r'\x11223344',
      'one_time_prekey_id': 99,
      'one_time_prekey_pub': r'\xdeadbeef',
    };

    final b = DeviceBundle.fromRow(row);
    expect(b.deviceNum, 2);
    expect(b.registrationId, 1234);
    expect(b.identityPub, Uint8List.fromList([5, 1, 2, 3, 4]));
    expect(b.signedPrekeyId, 7);
    expect(b.signedPrekeyPub, Uint8List.fromList([0xaa, 0xbb, 0xcc, 0xdd]));
    expect(b.signedPrekeySig, Uint8List.fromList([0x11, 0x22, 0x33, 0x44]));
    expect(b.oneTimePrekeyId, 99);
    expect(b.oneTimePrekeyPub, Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]));
  });

  test('DeviceBundle.fromRow decodes List<int> bytea input', () {
    // Some contexts may pass bytea as List<int> already
    final row = <String, dynamic>{
      'device_num': 3,
      'registration_id': 5678,
      'identity_pub': [5, 1, 2, 3],
      'signed_prekey_id': 42,
      'signed_prekey_pub': [0xaa, 0xbb, 0xcc],
      'signed_prekey_sig': [0x99, 0x88],
      'one_time_prekey_id': 55,
      'one_time_prekey_pub': [0x01, 0x02],
    };

    final b = DeviceBundle.fromRow(row);
    expect(b.deviceNum, 3);
    expect(b.registrationId, 5678);
    expect(b.identityPub, Uint8List.fromList([5, 1, 2, 3]));
    expect(b.signedPrekeyId, 42);
    expect(b.signedPrekeyPub, Uint8List.fromList([0xaa, 0xbb, 0xcc]));
    expect(b.signedPrekeySig, Uint8List.fromList([0x99, 0x88]));
    expect(b.oneTimePrekeyId, 55);
    expect(b.oneTimePrekeyPub, Uint8List.fromList([0x01, 0x02]));
  });

  test('DeviceBundle.fromRow handles exhausted one-time prekeys (nulls)', () {
    // When a device has no more one-time prekeys, both fields are null
    final row = <String, dynamic>{
      'device_num': 1,
      'registration_id': 999,
      'identity_pub': r'\x0a0b0c0d',
      'signed_prekey_id': 1,
      'signed_prekey_pub': r'\xffeeddcc',
      'signed_prekey_sig': r'\xaabbccdd',
      'one_time_prekey_id': null,
      'one_time_prekey_pub': null,
    };

    final b = DeviceBundle.fromRow(row);
    expect(b.deviceNum, 1);
    expect(b.registrationId, 999);
    expect(b.signedPrekeyId, 1);
    expect(b.oneTimePrekeyId, isNull);
    expect(b.oneTimePrekeyPub, isNull);
  });

  test('DeviceBundle.fromRow maps scalar columns correctly', () {
    // Verify that all non-bytea columns are correctly mapped
    final row = <String, dynamic>{
      'device_num': 5,
      'registration_id': 12345,
      'identity_pub': r'\xaa',
      'signed_prekey_id': 777,
      'signed_prekey_pub': r'\xbb',
      'signed_prekey_sig': r'\xcc',
      'one_time_prekey_id': 888,
      'one_time_prekey_pub': r'\xdd',
    };

    final b = DeviceBundle.fromRow(row);
    expect(b.deviceNum, 5);
    expect(b.registrationId, 12345);
    expect(b.signedPrekeyId, 777);
    expect(b.oneTimePrekeyId, 888);
  });

  test('PreKeyBundleSource exposes a non-consuming roster and a single-device fetch', () {
    // Compile-time contract check: a fake must satisfy exactly these members.
    final fake = _FakeSource();
    expect(fake, isA<PreKeyBundleSource>());
  });
}

class _FakeSource implements PreKeyBundleSource {
  @override
  Future<List<int>> deviceNumsFor(String userId) async => [1, 2];

  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async => null;
}
