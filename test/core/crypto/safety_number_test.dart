import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:lovinity/core/crypto/safety_number.dart';

void main() {
  test('both spouses see the same 60 digits; a swapped key changes them', () {
    final a = generateIdentityKeyPair().getPublicKey();
    final b = generateIdentityKeyPair().getPublicKey();
    final mallory = generateIdentityKeyPair().getPublicKey();

    final fromA = safetyNumber(
      selfId: 'a',
      selfKey: a,
      spouseId: 'b',
      spouseKeys: [b],
    );
    final fromB = safetyNumber(
      selfId: 'b',
      selfKey: b,
      spouseId: 'a',
      spouseKeys: [a],
    );
    expect(fromA, matches(RegExp(r'^\d{60}$')));
    expect(fromA, fromB);
    expect(
      safetyNumber(
        selfId: 'a',
        selfKey: a,
        spouseId: 'b',
        spouseKeys: [mallory],
      ),
      isNot(fromA),
    );
  });
}
