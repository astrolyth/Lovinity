// lib/core/notifications/activity_detectors.dart
//
// Pure helpers that turn a Supabase realtime stream's "full snapshot on
// every change" emissions into partner-activity notifications, without a
// server-side event feed. No Riverpod/Drift dependency so they're testable
// in isolation; see docs/superpowers/specs/2026-08-01-notification-inbox-v2-design.md.

/// Returns a stream-listener callback that invokes [onNew] once for every
/// element present in a new emission that wasn't present in the previous
/// one (keyed by [keyOf]). Never fires on the very first emission -- that's
/// existing state the stream loads on subscribe, not new activity.
void Function(List<T> rows) newRowDetector<T>({
  required String Function(T row) keyOf,
  required void Function(T row) onNew,
}) {
  Set<String>? previousKeys;
  return (rows) {
    final current = {for (final row in rows) keyOf(row): row};
    if (previousKeys != null) {
      for (final entry in current.entries) {
        if (!previousKeys!.contains(entry.key)) onNew(entry.value);
      }
    }
    previousKeys = current.keys.toSet();
  };
}

/// True when pairing just became active -- [previousStatus] was not
/// `'active'` and [nextStatus] is. Pass `couple?.status` at each stream
/// emission (null when unpaired/no couple row yet).
bool pairingJustActivated(String? previousStatus, String? nextStatus) {
  final wasActive = previousStatus == 'active';
  final isActive = nextStatus == 'active';
  return !wasActive && isActive;
}
