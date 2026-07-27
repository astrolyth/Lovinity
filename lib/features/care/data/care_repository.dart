import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/models/care_tip.dart';

class CareRepository {
  CareRepository(this._client);
  final SupabaseClient _client;

  Future<List<CareTip>> fetchForAudience(String audience) async {
    final rows = await _client
        .from('cycle_care_tips')
        .select()
        .eq('audience', audience)
        .order('sort_order');
    return [for (final r in rows) CareTip.fromRow(Map<String, dynamic>.from(r as Map))];
  }
}
