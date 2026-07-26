import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:lovinity/core/crypto/key_vault.dart';
import 'package:lovinity/core/crypto/secure_store.dart';
import 'package:lovinity/core/crypto/signal_keys.dart';
import 'package:lovinity/core/crypto/stores/drift_signal_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  test('satisfies SignalProtocolStore across all four interfaces', () async {
    final db = SignalDb.memory();
    addTearDown(db.close);
    final vault = KeyVault(InMemorySecureStore());
    final generated = generateBundle(deviceId: 'd', oneTimePrekeyCount: 1);
    await vault.savePrivate(generated.private);

    final store = DriftSignalStore(db, vault);
    expect(store, isA<SignalProtocolStore>());

    // identity
    expect(await store.getLocalRegistrationId(),
        generated.private.registrationId);
    // session
    final addr = SignalProtocolAddress('bob', 1);
    await store.storeSession(addr, SessionRecord());
    expect(await store.containsSession(addr), isTrue);
    // prekey
    final pk = generatePreKeys(1, 1).first;
    await store.storePreKey(pk.id, pk);
    expect(await store.containsPreKey(pk.id), isTrue);
    // signed prekey
    final spk = generateSignedPreKey(
        IdentityKeyPair.fromSerialized(generated.private.identitySerialized), 1);
    await store.storeSignedPreKey(spk.id, spk);
    expect(await store.containsSignedPreKey(spk.id), isTrue);
  });
}
