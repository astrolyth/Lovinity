import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/share_intake.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';

/// Accepts a share only when signed in AND paired, storing it for the Wall
/// screen. Signed-out/unpaired shares are dropped (not held across sign-in).
/// Waits for the auth session first: on cold start the couple provider
/// briefly reports null before the restored session arrives.
final acceptShareProvider = Provider<Future<bool> Function(SharedPayload)>((ref) {
  return (payload) async {
    final session = await ref
        .read(authSessionProvider.future)
        .timeout(const Duration(seconds: 10));
    if (session == null) return false;
    final couple = await ref
        .read(currentCoupleProvider.future)
        .timeout(const Duration(seconds: 10));
    if (couple == null) return false;
    ref.read(pendingShareProvider.notifier).set(payload);
    return true;
  };
});
