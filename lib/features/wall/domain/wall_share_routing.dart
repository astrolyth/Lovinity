import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/share_intake.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';

/// Accepts a share only when signed in AND paired, storing it for the Wall
/// screen. Signed-out/unpaired shares are dropped (not held across sign-in).
/// Waits for the auth session first: on cold start the couple provider
/// briefly reports null before the restored session arrives. Also waits for
/// the own profile and requires onboarding to be done: the router redirects
/// every non-splash path to /splash until the profile resolves (and to
/// /onboarding while gender is unset), which would swallow the navigation and
/// leave a stale pending share behind.
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
    final profile = await ref
        .read(ownProfileProvider.future)
        .timeout(const Duration(seconds: 10));
    if (profile == null || profile.gender == null) return false;
    ref.read(pendingShareProvider.notifier).set(payload);
    return true;
  };
});
