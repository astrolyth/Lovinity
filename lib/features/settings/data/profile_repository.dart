import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes to the caller's own `public.users` profile row from Settings.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  /// [madhhab] must be 'shafi' or 'hanafi' (enforced by a DB check constraint).
  /// Changing it moves the Asr calculation, so callers should invalidate the
  /// profile afterwards to recompute prayer times.
  Future<void> updateMadhhab({
    required String userId,
    required String madhhab,
  }) async {
    await _client.from('users').update({
      'madhhab': madhhab,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }
}
