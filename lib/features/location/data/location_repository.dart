import 'package:supabase_flutter/supabase_flutter.dart';

class LocationRepository {
  LocationRepository(this._client);
  final SupabaseClient _client;

  /// Persist the user's coordinates + IANA timezone on their profile row.
  Future<void> updateLocation({
    required String userId,
    required double latitude,
    required double longitude,
    required String timezone,
  }) async {
    await _client.from('users').update({
      'latitude': latitude,
      'longitude': longitude,
      'timezone': timezone,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }
}
