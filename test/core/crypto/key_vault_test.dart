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

  test('scoped vaults over ONE shared store keep accounts separate', () async {
    // Two accounts on the same device share the Keychain; the scope must keep
    // their identity and device number from colliding.
    final store = InMemorySecureStore();
    final a = KeyVault(store, scope: 'user-A');
    final b = KeyVault(store, scope: 'user-B');

    await a.savePrivate(
        generateBundle(deviceId: 'a', oneTimePrekeyCount: 1).private);
    await a.saveDeviceNum(1);

    expect(await b.hasIdentity(), isFalse);
    expect(await b.readDeviceNum(), isNull);

    await b.savePrivate(
        generateBundle(deviceId: 'b', oneTimePrekeyCount: 1).private);
    await b.saveDeviceNum(2);

    expect(await a.readDeviceNum(), 1,
        reason: "B registering must not overwrite A's device number");
    expect(await a.readIdentity(), isNot(await b.readIdentity()));
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
