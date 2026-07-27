import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/crypto/key_counters.dart';
import 'package:lovinity/core/storage/signal_db.dart';

void main() {
  late SignalDb db;
  setUp(() => db = SignalDb.memory());
  tearDown(() => db.close());

  test('prekey ids start at 1 and never repeat across reservations', () async {
    final c = KeyCounters(db);

    expect(await c.nextPrekeyId(20), 1);
    // Second reservation must start AFTER the first block, never reuse ids:
    // a reissued id with different key material is silently undecryptable.
    expect(await c.nextPrekeyId(5), 21);
    expect(await c.nextPrekeyId(1), 26);
  });

  test('signed prekey ids start at 1 and increment', () async {
    final c = KeyCounters(db);

    expect(await c.nextSignedPrekeyId(), 1);
    expect(await c.nextSignedPrekeyId(), 2);
    expect(await c.nextSignedPrekeyId(), 3);
  });

  test('counters are independent', () async {
    final c = KeyCounters(db);

    await c.nextPrekeyId(10);
    expect(await c.nextSignedPrekeyId(), 1,
        reason: 'signed prekey counter must not be advanced by prekeys');
  });

  test('counters persist across KeyCounters instances (same db)', () async {
    await KeyCounters(db).nextPrekeyId(20);

    // Simulates an app restart: new instance, same database.
    expect(await KeyCounters(db).nextPrekeyId(1), 21);
  });
}
