import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/letter_crypto.dart';
import '../../../core/crypto/secure_store.dart';
import '../../../core/notifications/activity_detectors.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../auth/domain/auth_controller.dart';
import '../../chat/domain/chat_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/letter_repository.dart';

final letterRepositoryProvider = Provider<LetterRepository>((ref) {
  return LetterRepository(ref.read(supabaseClientProvider));
});

final letterKeyServiceProvider = Provider<LetterKeyService>((ref) {
  return LetterKeyService(
    FlutterSecureStore(ref.read(secureStorageProvider)),
  );
});

/// Letters this user is allowed to see.
final lettersProvider = StreamProvider<List<LetterSummary>>((ref) {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return const Stream.empty();
  return ref.read(letterRepositoryProvider).watchLetters(coupleId: coupleId);
});

/// Letters you wrote that are still sealed — yours to review or withdraw.
List<LetterSummary> sealedByMe({
  required List<LetterSummary> letters,
  required String selfId,
  required DateTime now,
}) =>
    [
      for (final l in letters)
        if (l.authorId == selfId && !l.isUnlockedAt(now)) l,
    ];

/// Letters that have opened, newest unlock first.
///
/// Includes your own: an opened letter is part of the couple's shared history,
/// and the author re-reading what they wrote years ago is the point.
List<LetterSummary> opened({
  required List<LetterSummary> letters,
  required DateTime now,
}) {
  final result = [
    for (final l in letters)
      if (l.isUnlockedAt(now)) l,
  ];
  result.sort((a, b) => b.unlockAt.compareTo(a.unlockAt));
  return result;
}

final sealedLettersProvider = Provider<List<LetterSummary>>((ref) {
  final letters = ref.watch(lettersProvider).asData?.value ?? const [];
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  if (selfId == null) return const [];
  return sealedByMe(letters: letters, selfId: selfId, now: now);
});

final openedLettersProvider = Provider<List<LetterSummary>>((ref) {
  final letters = ref.watch(lettersProvider).asData?.value ?? const [];
  final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
  return opened(letters: letters, now: now);
});

/// Ensures this device holds the couple's letter key, and that the spouse has
/// it too.
///
/// Returns null when no key can be established — the caller must then refuse
/// to seal a letter rather than write one nobody can ever open.
///
/// The generating device sends the key to the spouse over the Signal session
/// (`ChatService.sendLetterKey`). If that delivery fails, the freshly generated
/// key is discarded: keeping it would leave the two devices holding different
/// keys, and every letter written afterwards would be permanently unreadable by
/// the person it was written for.
final ensureLetterKeyProvider =
    FutureProvider.autoDispose<Uint8List?>((ref) async {
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (coupleId == null) return null;

  final service = ref.read(letterKeyServiceProvider);
  final existing = await service.read(coupleId);
  if (existing != null) return existing;

  final chat = await ref.read(chatServiceProvider.future);
  if (chat == null) return null;

  final result = await service.ensure(coupleId);
  if (result.existed) return result.key;

  final delivered = await chat.sendLetterKey(result.key);
  if (!delivered) {
    await service.clear(coupleId);
    return null;
  }
  return result.key;
});

/// Notifies when a letter opens, or when the spouse seals a new one for you.
///
/// Seals are announced without content — knowing a letter is waiting is part
/// of the anticipation, and the RLS seal means this device could not reveal
/// what it says even if it tried.
final letterNotificationPumpProvider = Provider<void>((ref) {
  final selfId =
      ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
  final coupleId =
      ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
  if (selfId == null || coupleId == null) return;
  final store = ref.read(notificationStoreProvider);

  final detector = newRowDetector<LetterSummary>(
    keyOf: (l) => l.id,
    onNew: (letter) {
      if (letter.authorId == selfId) return;
      // A spouse's letter only becomes visible to this device at the moment it
      // unlocks, so any new row here is a letter that has just opened.
      unawaited(store.insertBestEffort(
        kind: 'letter',
        title: 'A letter from your partner has opened',
        route: '/home/letters',
      ));
    },
  );

  final sub = ref
      .read(letterRepositoryProvider)
      .watchLetters(coupleId: coupleId)
      .listen(detector);
  ref.onDispose(sub.cancel);
});
