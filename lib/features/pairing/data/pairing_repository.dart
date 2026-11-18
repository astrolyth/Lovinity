import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';
import '../../../shared/models/couple.dart';

class PairingInvite {
  const PairingInvite({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
}

class PairingRepository {
  PairingRepository(this._client);

  final SupabaseClient _client;

  Future<PairingInvite> createInvite() async {
    try {
      final result = await _client.rpc('create_pairing_invite');
      // SETOF/TABLE returning RPC → list of rows.
      final row = (result is List)
          ? Map<String, dynamic>.from(result.first as Map)
          : Map<String, dynamic>.from(result as Map);
      return PairingInvite(
        code: row['code'] as String,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } on PostgrestException catch (e) {
      throw PairingFailure.fromRpcCode(e.message);
    }
  }

  Future<Couple> acceptInvite(String code) async {
    try {
      final row = await _client.rpc('accept_pairing_invite', params: {
        'p_code': code.toUpperCase(),
      });
      final data = (row is List) ? row.firstOrNull : row;
      // A wrong code returns no row rather than raising, so the server can
      // count it toward the attempt limit (20261118000001).
      if (data is! Map || data['id'] == null) {
        throw PairingFailure.fromRpcCode('invite_not_found');
      }
      return Couple.fromRow(Map<String, dynamic>.from(data));
    } on PostgrestException catch (e) {
      throw PairingFailure.fromRpcCode(e.message);
    }
  }

  /// Watches the couples table for a row involving this user; emits when
  /// pairing completes on the inviter side.
  Stream<Couple?> watchCurrentCouple(String userId) {
    return _client
        .from('couples')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final match = rows.firstWhere(
            (r) =>
                r['member_a'] == userId ||
                r['member_b'] == userId,
            orElse: () => <String, dynamic>{},
          );
          if (match.isEmpty) return null;
          return Couple.fromRow(match);
        });
  }

  Future<Couple?> fetchCurrentCouple(String userId) async {
    final rows = await _client
        .from('couples')
        .select()
        .or('member_a.eq.$userId,member_b.eq.$userId')
        .eq('status', 'active')
        .limit(1);
    if (rows.isEmpty) return null;
    return Couple.fromRow(Map<String, dynamic>.from(rows.first));
  }
}
