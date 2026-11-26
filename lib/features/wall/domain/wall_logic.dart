import 'package:intl/intl.dart';

import 'wall_models.dart';

/// Compact relative time for Wall cards: now, 5m, 3h, 2d, then "1 Sep".
String formatWallTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return DateFormat('d MMM').format(t);
}

/// Per-kind counts for one item, in [WallReactionKind] order, zero counts
/// omitted. `mine` is true when [selfId] left that reaction.
List<ReactionCount> summarizeReactions(
  Iterable<WallReaction> reactions, {
  required String itemId,
  required String? selfId,
}) {
  final counts = <WallReactionKind, int>{};
  final mine = <WallReactionKind>{};
  for (final r in reactions) {
    if (r.itemId != itemId) continue;
    counts[r.kind] = (counts[r.kind] ?? 0) + 1;
    if (r.userId == selfId) mine.add(r.kind);
  }
  return [
    for (final k in WallReactionKind.values)
      if ((counts[k] ?? 0) > 0)
        ReactionCount(kind: k, count: counts[k]!, mine: mine.contains(k)),
  ];
}

/// Overlays not-yet-confirmed toggles ([pending]: kind -> wanted "mine"
/// state) on the server summary, so a tap shows instantly.
List<ReactionCount> applyPendingReactions(
  List<ReactionCount> server,
  Map<WallReactionKind, bool> pending,
) {
  if (pending.isEmpty) return server;
  final byKind = {for (final r in server) r.kind: r};
  final out = <ReactionCount>[];
  for (final kind in WallReactionKind.values) {
    final s = byKind[kind];
    var count = s?.count ?? 0;
    var mine = s?.mine ?? false;
    final want = pending[kind];
    if (want != null && want != mine) {
      count += want ? 1 : -1;
      mine = want;
    }
    if (count > 0) out.add(ReactionCount(kind: kind, count: count, mine: mine));
  }
  return out;
}

/// Spouse items newer than [lastVisit]; every spouse item if never visited.
Set<String> unseenItemIds(
  Iterable<WallItem> items, {
  required String? selfId,
  required DateTime? lastVisit,
}) {
  if (selfId == null) return const {};
  return {
    for (final i in items)
      if (i.addedBy != selfId &&
          (lastVisit == null || i.createdAt.isAfter(lastVisit)))
        i.id,
  };
}

/// Items created in the 7 days before [now].
int itemsThisWeek(Iterable<WallItem> items, {required DateTime now}) {
  final from = now.subtract(const Duration(days: 7));
  return items.where((i) => i.createdAt.isAfter(from)).length;
}
