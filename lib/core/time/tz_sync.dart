import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../features/auth/domain/auth_controller.dart';
import '../../features/home/domain/home_providers.dart';
import '../../shared/providers/supabase_provider.dart';

/// Keeping each spouse's IANA timezone honest.
///
/// The prayer log renders two day anchors — yours and your spouse's. Yours
/// comes from this device; hers can only reach you through her `users.timezone`
/// row. That column used to be written *only* when the user tapped "Set your
/// location", so anyone who travelled kept publishing a stale zone and their
/// partner's screen rendered their day (and the dual clock) in the wrong
/// place, confidently.
///
/// The split of responsibility here:
///
///   * **Device zone is authoritative for you.** Your own column, and the day
///     key your check-ins are written under, come from [deviceTimezoneProvider].
///     That value is correct the instant you land, with no network and no
///     permission prompt — so your own log is never wrong even if the publish
///     below fails or you are offline.
///   * **`users.timezone` is a publication channel, not a source of truth.**
///     [timezonePublishProvider] mirrors the device zone into it purely so your
///     spouse can resolve your day.
///
/// Reading the zone needs no location permission, which is what makes silent
/// syncing acceptable here. Coordinates are deliberately *not* touched: those
/// do require permission, and prayer-time accuracy after a move is handled by
/// the separate, user-initiated location flow.

/// Reads the device's current IANA zone identifier. Indirected through a
/// provider so tests can substitute a fake instead of the platform channel.
typedef DeviceTimezoneReader = Future<String> Function();

Future<String> _platformDeviceTimezone() async {
  final tz = await FlutterTimezone.getLocalTimezone();
  return tz.identifier;
}

final deviceTimezoneReaderProvider =
    Provider<DeviceTimezoneReader>((ref) => _platformDeviceTimezone);

/// The device's current IANA timezone, re-read whenever the app resumes.
///
/// Resume is the moment that matters: a timezone change almost always happens
/// while the app is backgrounded (a flight, a border, a DST switch overnight).
/// Falls back to `UTC` rather than throwing — a platform-channel failure must
/// not be able to take down the prayer log.
class DeviceTimezone extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final listener = AppLifecycleListener(onResume: () => unawaited(refresh()));
    ref.onDispose(listener.dispose);
    return _read();
  }

  Future<String> _read() async {
    try {
      return await ref.read(deviceTimezoneReaderProvider)();
    } catch (_) {
      return 'UTC';
    }
  }

  /// Re-reads the device zone, emitting only on an actual change so resuming
  /// the app doesn't needlessly churn every watcher of this provider.
  Future<void> refresh() async {
    final next = await _read();
    if (next != state.asData?.value) state = AsyncData(next);
  }
}

final deviceTimezoneProvider =
    AsyncNotifierProvider<DeviceTimezone, String>(DeviceTimezone.new);

/// Holds the zone value this session has already attempted to publish.
///
/// Lives in its own provider so it survives rebuilds of
/// [timezonePublishProvider], whose body re-runs whenever its dependencies
/// change — that persistence is what makes it usable as a loop guard.
///
/// A plain mutable holder rather than a `StateProvider`: nothing should ever
/// rebuild in response to this changing, and writing to a `StateProvider` from
/// inside another provider's build would do exactly that.
class _PublishGuard {
  String? attempted;
}

final _publishGuardProvider = Provider<_PublishGuard>((ref) => _PublishGuard());

/// Mirrors the device zone into `users.timezone` when the two disagree, so the
/// spouse's device can anchor this user's day correctly. Watched once from
/// HomeScreen, alongside the notification pumps.
///
/// Best-effort by design: a failed write leaves the local experience fully
/// correct (the device zone still drives this user's own side), so there is no
/// user-actionable failure to surface.
///
/// Guarded against re-entry. This provider watches [ownProfileProvider] and
/// then invalidates it, which is a cycle: if a write ever succeeded *without*
/// changing the stored value — a constraint, a trigger, an RLS policy that
/// silently filters the update — the refetched profile would still disagree
/// with the device zone and we would write, invalidate, and refetch forever,
/// hammering the database. Recording the attempted value breaks that cycle:
/// each distinct zone is published at most once per session.
final timezonePublishProvider = Provider<void>((ref) {
  final deviceTz = ref.watch(deviceTimezoneProvider).asData?.value;
  final profile = ref.watch(ownProfileProvider).asData?.value;
  final session = ref.watch(authSessionProvider).asData?.value;
  if (deviceTz == null || profile == null || session == null) return;
  if (profile.timezone == deviceTz) return;
  final guard = ref.read(_publishGuardProvider);
  if (guard.attempted == deviceTz) return;
  guard.attempted = deviceTz;

  unawaited(() async {
    try {
      await ref
          .read(supabaseClientProvider)
          .from('users')
          .update({'timezone': deviceTz}).eq('id', session.user.id);
      // Re-read so the new zone is reflected locally.
      ref.invalidate(ownProfileProvider);
    } catch (_) {
      // Cleared so a transient failure (offline at launch) can be retried the
      // next time this provider's dependencies change, rather than leaving the
      // zone unpublished until the app restarts.
      guard.attempted = null;
    }
  }());
});
