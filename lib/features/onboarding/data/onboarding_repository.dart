import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingRepository {
  OnboardingRepository(this._client);
  final SupabaseClient _client;

  Future<void> saveProfile({
    required String userId,
    required String displayName,
    required String gender,
    required String madhhab,
    String? timezone,
    double? latitude,
    double? longitude,
  }) async {
    final data = <String, dynamic>{
      'display_name': displayName,
      'gender': gender,
      'madhhab': madhhab,
      if (timezone != null) 'timezone': timezone,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _client.from('users').update(data).eq('id', userId);
  }
}
