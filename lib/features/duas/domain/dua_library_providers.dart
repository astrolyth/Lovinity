import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../data/dua_library_repository.dart';

final duaLibraryRepositoryProvider = Provider<DuaLibraryRepository>((ref) {
  return DuaLibraryRepository(ref.read(supabaseClientProvider));
});

/// Approved library, cached for the session (small, rarely changes).
final duaLibraryProvider =
    FutureProvider.autoDispose<List<LibraryDua>>((ref) async {
  final list = await ref.read(duaLibraryRepositoryProvider).fetchApproved();
  // Keep-alive only after success, so a failed fetch retries on next load.
  if (ref.mounted) ref.keepAlive();
  return list;
});
