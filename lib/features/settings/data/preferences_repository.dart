import 'package:supabase_flutter/supabase_flutter.dart';

class PreferencesRepository {
  PreferencesRepository(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> fetch(String userId) async {
    final row = await _client
        .from('user_preferences')
        .select('prefs')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(row['prefs'] as Map);
  }

  Future<void> setKey({
    required String userId,
    required String key,
    required dynamic value,
    Map<String, dynamic> current = const {},
  }) async {
    final merged = {...current, key: value};
    await _client.from('user_preferences').upsert({
      'user_id': userId,
      'prefs': merged,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
