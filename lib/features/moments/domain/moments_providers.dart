import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/supabase_provider.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/moments_repository.dart';
import 'moment.dart';

final momentsRepositoryProvider = Provider<MomentsRepository>((ref) {
  return MomentsRepository(ref.read(supabaseClientProvider));
});

/// Newest first, realtime.
final momentsProvider = StreamProvider<List<Moment>>((ref) {
  final coupleId = ref.watch(
    currentCoupleProvider.select((c) => c.asData?.value?.id),
  );
  if (coupleId == null) return Stream.value(const []);
  return ref.read(momentsRepositoryProvider).watch(coupleId);
});

/// Reactions and comments for the couple, oldest first, realtime.
final momentRepliesProvider = StreamProvider<List<MomentReply>>((ref) {
  final coupleId = ref.watch(
    currentCoupleProvider.select((c) => c.asData?.value?.id),
  );
  if (coupleId == null) return Stream.value(const []);
  return ref.read(momentsRepositoryProvider).watchReplies(coupleId);
});

/// Signed URL kept 50 min so it re-signs before the 1-hour expiry.
final momentSignedUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) async {
      final url = await ref.read(momentsRepositoryProvider).signedUrl(path);
      if (ref.mounted) {
        ref.keepAlive();
        final timer = Timer(const Duration(minutes: 50), ref.invalidateSelf);
        ref.onDispose(timer.cancel);
      }
      return url;
    });
