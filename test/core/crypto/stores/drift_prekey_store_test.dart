import 'package:flutter_test/flutter_test.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:lovinity/core/crypto/stores/drift_prekey_store.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  setUp(() => db = SignalDb.memory());
  tearDown(() => db.close());

  test('prekey round-trips, reports presence, and removes', () async {
    final store = DriftPreKeyStore(db);
    final record = generatePreKeys(1, 1).first;

    expect(await store.containsPreKey(record.id), isFalse);
    await store.storePreKey(record.id, record);
    expect(await store.containsPreKey(record.id), isTrue);

    final loaded = await store.loadPreKey(record.id);
    expect(loaded.serialize(), record.serialize());

    await store.removePreKey(record.id);
    expect(await store.containsPreKey(record.id), isFalse);
  });

  test('loadPreKey throws InvalidKeyIdException when missing', () async {
    final store = DriftPreKeyStore(db);
    expect(() => store.loadPreKey(999), throwsA(isA<InvalidKeyIdException>()));
  });

  test('signed prekey round-trips and lists', () async {
    final store = DriftSignedPreKeyStore(db);
    final identity = generateIdentityKeyPair();
    final signed = generateSignedPreKey(identity, 1);

    await store.storeSignedPreKey(signed.id, signed);
    expect(await store.containsSignedPreKey(signed.id), isTrue);
    expect((await store.loadSignedPreKey(signed.id)).serialize(),
        signed.serialize());
    expect((await store.loadSignedPreKeys()).length, 1);

    await store.removeSignedPreKey(signed.id);
    expect(await store.containsSignedPreKey(signed.id), isFalse);
  });
}
