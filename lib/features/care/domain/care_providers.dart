import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/care_tip.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../data/care_repository.dart';

final careRepositoryProvider = Provider<CareRepository>((ref) {
  return CareRepository(ref.read(supabaseClientProvider));
});

/// Tips for the current user's role (wife -> self-care, husband -> support).
final careTipsProvider = FutureProvider<List<CareTip>>((ref) async {
  final audience = ref.watch(isWifeProvider) ? 'wife' : 'husband';
  return ref.read(careRepositoryProvider).fetchForAudience(audience);
});
