import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart' as sig;
import 'package:lovinity/core/crypto/signal_keys.dart';

void main() {
  test('generateBundle produces a signed prekey verifiable against identity',
      () {
    final bundle = generateBundle(deviceId: 'test-device', oneTimePrekeyCount: 3);

    // Identity public key should verify the SPK signature.
    final identityPub = sig.Curve.decodePoint(bundle.public.identityPub, 0);
    final verified = sig.Curve.verifySignature(
      identityPub,
      bundle.public.signedPrekeyPub,
      bundle.public.signedPrekeySig,
    );

    expect(verified, isTrue);
  });

  test('generateBundle yields the requested number of one-time prekeys', () {
    final bundle = generateBundle(deviceId: 'd', oneTimePrekeyCount: 7);
    expect(bundle.public.oneTimePrekeys, hasLength(7));
    expect(bundle.private.oneTimePrekeysSerialized, hasLength(7));
  });

  test('two invocations produce distinct identity keys', () {
    final a = generateBundle(deviceId: 'a', oneTimePrekeyCount: 1);
    final b = generateBundle(deviceId: 'b', oneTimePrekeyCount: 1);
    expect(a.public.identityPub, isNot(equals(b.public.identityPub)));
  });

  test('generateBundle honours explicit starting ids', () {
    final b = generateBundle(
      deviceId: 'd',
      oneTimePrekeyCount: 3,
      firstPrekeyId: 100,
      signedPrekeyId: 7,
    );

    expect(b.public.signedPrekeyId, 7);
    expect(b.public.oneTimePrekeys.map((p) => p.id).toList(), [100, 101, 102]);
    expect(b.private.oneTimePrekeysSerialized.keys.toList()..sort(),
        [100, 101, 102]);
  });

  test('generateBundle defaults are unchanged (ids start at 1)', () {
    final b = generateBundle(deviceId: 'd', oneTimePrekeyCount: 2);

    expect(b.public.signedPrekeyId, 1);
    expect(b.public.oneTimePrekeys.map((p) => p.id).toList(), [1, 2]);
  });

  test('generatePrekeyBatch numbers from the given first id', () {
    final batch = generatePrekeyBatch(firstPrekeyId: 50, count: 3);

    expect(batch.publics.map((p) => p.id).toList(), [50, 51, 52]);
    expect(batch.privateSerialized.keys.toList()..sort(), [50, 51, 52]);
  });
}
