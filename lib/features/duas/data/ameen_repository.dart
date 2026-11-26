import 'package:supabase_flutter/supabase_flutter.dart';

/// One "Ameen" on the day's dua.
typedef Ameen = ({String userId, String day, DateTime saidAt});

/// "Ameen together": one Ameen per person per local day (`dua_ameens`).
class AmeenRepository {
  AmeenRepository(this._client);
  final SupabaseClient _client;

  /// Idempotent: a second tap the same day is a no-op.
  Future<void> say({
    required String coupleId,
    required String userId,
    required String day,
  }) => _client
      .from('dua_ameens')
      .upsert(
        {'couple_id': coupleId, 'user_id': userId, 'day': day},
        onConflict: 'user_id,day',
        ignoreDuplicates: true,
      );

  /// The couple's recent Ameens, newest days first.
  Stream<List<Ameen>> watch(String coupleId) => _client
      .from('dua_ameens')
      .stream(primaryKey: ['id'])
      .eq('couple_id', coupleId)
      .order('day')
      .limit(14)
      .map(
        (rows) => [
          for (final r in rows)
            (
              userId: r['user_id'] as String,
              day: r['day'] as String,
              saidAt: DateTime.parse(r['said_at'] as String),
            ),
        ],
      );
}
