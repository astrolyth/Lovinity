import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/gratitude_repository.dart';

final gratitudeRepositoryProvider = Provider<GratitudeRepository>((ref) {
  return GratitudeRepository(ref.read(supabaseClientProvider));
});

/// All notes for the couple, newest first.
final gratitudeNotesProvider =
    StreamProvider<List<GratitudeNote>>((ref) {
  final couple = ref.watch(currentCoupleProvider).asData?.value;
  if (couple == null) return const Stream.empty();
  return ref.read(gratitudeRepositoryProvider).watchAll(couple.id);
});

/// Whether the current user already wrote a note today.
final wroteGratitudeTodayProvider = Provider<bool>((ref) {
  final notes = ref.watch(gratitudeNotesProvider).asData?.value ?? const [];
  final session = ref.watch(authSessionProvider).asData?.value;
  if (session == null) return false;
  final today = DateTime.now();
  return notes.any((n) =>
      n.authorId == session.user.id &&
      n.createdAt.year == today.year &&
      n.createdAt.month == today.month &&
      n.createdAt.day == today.day);
});
