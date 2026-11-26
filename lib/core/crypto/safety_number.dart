import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../../features/auth/domain/auth_controller.dart'
    show authSessionProvider, keyVaultProvider;
import '../../features/pairing/domain/pairing_providers.dart';
import 'crypto_providers.dart';

/// Signal-style safety number: 60 digits that are identical on both phones
/// when neither side's identity key has been swapped. Order-independent, so
/// [selfId]/[spouseId] can be passed from either side.
String safetyNumber({
  required String selfId,
  required IdentityKey selfKey,
  required String spouseId,
  required List<IdentityKey> spouseKeys,
}) => NumericFingerprintGenerator(5200)
    .createListFor(
      2,
      Uint8List.fromList(utf8.encode(selfId)),
      [selfKey],
      Uint8List.fromList(utf8.encode(spouseId)),
      spouseKeys,
    )
    .displayableFingerprint
    .getDisplayText();

/// This device's safety number with the spouse, from the identities it
/// already trusts in its sessions (never a fresh server fetch, which would
/// spend a one-time prekey). Null until a session with the spouse exists.
final safetyNumberProvider = FutureProvider.autoDispose<String?>((ref) async {
  final self = ref.watch(authSessionProvider).asData?.value?.user.id;
  final spouse = self == null
      ? null
      : ref.watch(currentCoupleProvider).asData?.value?.spouseOf(self);
  if (self == null || spouse == null) return null;
  final own = await ref.read(keyVaultProvider(self)).readIdentity();
  if (own == null) return null;
  final db = ref.read(signalDbProvider(self));
  final rows = await (db.select(db.signalIdentities)
        ..where((t) => t.name.equals(spouse))
        ..orderBy([(t) => OrderingTerm.asc(t.deviceNum)]))
      .get();
  if (rows.isEmpty) return null;
  return safetyNumber(
    selfId: self,
    selfKey: IdentityKeyPair.fromSerialized(own).getPublicKey(),
    spouseId: spouse,
    spouseKeys: [for (final r in rows) IdentityKey.fromBytes(r.identityKey, 0)],
  );
});
