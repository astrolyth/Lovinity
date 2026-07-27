// lib/core/crypto/prekey_bundle_source.dart
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One device's published bundle. [oneTimePrekeyId]/[oneTimePrekeyPub] are null
/// when that device's one-time prekeys are exhausted — the handshake then
/// proceeds from the signed prekey alone, which is expected, not an error.
class DeviceBundle {
  const DeviceBundle({
    required this.deviceNum,
    required this.registrationId,
    required this.identityPub,
    required this.signedPrekeyId,
    required this.signedPrekeyPub,
    required this.signedPrekeySig,
    required this.oneTimePrekeyId,
    required this.oneTimePrekeyPub,
  });

  final int deviceNum;
  final int registrationId;
  final Uint8List identityPub;
  final int signedPrekeyId;
  final Uint8List signedPrekeyPub;
  final Uint8List signedPrekeySig;
  final int? oneTimePrekeyId;
  final Uint8List? oneTimePrekeyPub;

  PreKeyBundle toPreKeyBundle() => PreKeyBundle(
        registrationId,
        deviceNum,
        oneTimePrekeyId,
        oneTimePrekeyPub == null
            ? null
            : Curve.decodePoint(oneTimePrekeyPub!, 0),
        signedPrekeyId,
        Curve.decodePoint(signedPrekeyPub, 0),
        signedPrekeySig,
        IdentityKey.fromBytes(identityPub, 0),
      );

  factory DeviceBundle.fromRow(Map<String, dynamic> row) => DeviceBundle(
        deviceNum: row['device_num'] as int,
        registrationId: row['registration_id'] as int,
        identityPub: _bytes(row['identity_pub'])!,
        signedPrekeyId: row['signed_prekey_id'] as int,
        signedPrekeyPub: _bytes(row['signed_prekey_pub'])!,
        signedPrekeySig: _bytes(row['signed_prekey_sig'])!,
        oneTimePrekeyId: row['one_time_prekey_id'] as int?,
        oneTimePrekeyPub: _bytes(row['one_time_prekey_pub']),
      );

  /// Supabase returns bytea as a `\x…` hex string over PostgREST.
  static Uint8List? _bytes(Object? v) {
    if (v == null) return null;
    if (v is List) return Uint8List.fromList(v.cast<int>());
    final s = v as String;
    final hex = s.startsWith(r'\x') ? s.substring(2) : s;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

abstract class PreKeyBundleSource {
  /// The target's device numbers. Consumes NOTHING — this is called on every
  /// send to build the fan-out roster.
  Future<List<int>> deviceNumsFor(String userId);

  /// One device's bundle, consuming one one-time prekey server-side. Call this
  /// ONLY when establishing a session. Null when the device has no bundle.
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum);
}

class SupabasePreKeyBundleSource implements PreKeyBundleSource {
  SupabasePreKeyBundleSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<int>> deviceNumsFor(String userId) async {
    final rows = await _client.rpc(
      'list_devices',
      params: {'p_target_user': userId},
    );
    if (rows is! List) return const [];
    return rows
        .map((r) => (Map<String, dynamic>.from(r as Map))['device_num'] as int)
        .toList();
  }

  @override
  Future<DeviceBundle?> bundleFor(String userId, int deviceNum) async {
    final rows = await _client.rpc(
      'fetch_prekey_bundle',
      params: {'p_target_user': userId, 'p_device_num': deviceNum},
    );
    if (rows is! List || rows.isEmpty) return null;
    return DeviceBundle.fromRow(Map<String, dynamic>.from(rows.first as Map));
  }
}
