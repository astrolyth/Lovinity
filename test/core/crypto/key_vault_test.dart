import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_keys.dart';

void main() {
  test('round-trips registration id and device number', () async {
    final vault = KeyVault(InMemorySecureStore());
    final generated = generateBundle(deviceId: 'dev-1', oneTimePrekeyCount: 2);

    await vault.savePrivate(generated.private);
    await vault.saveDeviceNum(3);

    expect(await vault.readRegistrationId(), generated.private.registrationId);
    expect(await vault.readDeviceNum(), 3);
    expect(await vault.hasIdentity(), isTrue);
  });

  test('wipe clears registration id and device number', () async {
    final vault = KeyVault(InMemorySecureStore());
    await vault.savePrivate(
        generateBundle(deviceId: 'd', oneTimePrekeyCount: 1).private);
    await vault.saveDeviceNum(1);

    await vault.wipe();

    expect(await vault.readRegistrationId(), isNull);
    expect(await vault.readDeviceNum(), isNull);
  });

  test('two vaults with separate stores do not share state', () async {
    final a = KeyVault(InMemorySecureStore());
    final b = KeyVault(InMemorySecureStore());

    await a.savePrivate(generateBundle(deviceId: 'a', oneTimePrekeyCount: 1).private);

    expect(await a.hasIdentity(), isTrue);
    expect(await b.hasIdentity(), isFalse,
        reason: 'each simulated device must have an isolated vault');
  });
}
