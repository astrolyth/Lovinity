/// One live-camera photo or ≤3 s video sent to the spouse.
class Moment {
  const Moment({
    required this.id,
    required this.coupleId,
    required this.senderId,
    required this.mediaPath,
    required this.mediaMime,
    required this.createdAt,
    this.thumbPath,
    this.caption,
    this.viewedAt,
  });

  factory Moment.fromRow(Map<String, dynamic> r) => Moment(
    id: r['id'] as String,
    coupleId: r['couple_id'] as String,
    senderId: r['sender_id'] as String,
    mediaPath: r['media_path'] as String,
    mediaMime: r['media_mime'] as String,
    thumbPath: r['thumb_path'] as String?,
    caption: r['caption'] as String?,
    viewedAt: r['viewed_at'] == null
        ? null
        : DateTime.parse(r['viewed_at'] as String).toLocal(),
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
  );

  final String id;
  final String coupleId;
  final String senderId;
  final String mediaPath;
  final String mediaMime;
  final String? thumbPath;
  final String? caption;
  final DateTime? viewedAt;
  final DateTime createdAt;

  bool get isVideo => mediaMime.startsWith('video/');

  /// Path to show in a grid tile: the photo itself, or the video's thumbnail.
  String? get previewPath => isVideo ? thumbPath : mediaPath;
}

/// A moment's vlog day: days close at 4am local, so a 1am moment belongs to
/// the night before (the way people live their day, not the calendar).
DateTime vlogDay(DateTime local) {
  final shifted = local.subtract(const Duration(hours: 4));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Groups newest-first moments by [vlogDay], keeping order.
List<(DateTime, List<Moment>)> groupByDay(List<Moment> moments) {
  final out = <(DateTime, List<Moment>)>[];
  for (final m in moments) {
    final d = vlogDay(m.createdAt);
    if (out.isEmpty || out.last.$1 != d) out.add((d, []));
    out.last.$2.add(m);
  }
  return out;
}

/// Where the partner's story ring opens: their oldest unseen moment (so a
/// backlog plays in order), else their newest. Null if they have none.
Moment? partnerStoryStart(List<Moment> newestFirst, String selfId) {
  final theirs = newestFirst.where((m) => m.senderId != selfId);
  return theirs.where((m) => m.viewedAt == null).lastOrNull ??
      theirs.firstOrNull;
}

/// One split-screen frame of the daily vlog: the clock hour, plus up to one
/// moment from each spouse.
typedef VlogSlot = ({DateTime hour, Moment? partner, Moment? mine});

/// Oldest-first slots for a day's moments. Within an hour, each person's
/// moments pair up in order, so nothing is dropped when one sent more.
List<VlogSlot> vlogSlots(List<Moment> dayMoments, String selfId) {
  final byHour = <DateTime, (List<Moment>, List<Moment>)>{};
  final sorted = [...dayMoments]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final m in sorted) {
    final c = m.createdAt;
    final h = byHour.putIfAbsent(
      DateTime(c.year, c.month, c.day, c.hour),
      () => ([], []),
    );
    (m.senderId == selfId ? h.$2 : h.$1).add(m);
  }
  return [
    for (final MapEntry(key: hour, value: (theirs, mine)) in byHour.entries)
      for (
        var i = 0;
        i < (theirs.length > mine.length ? theirs.length : mine.length);
        i++
      )
        (
          hour: hour,
          partner: i < theirs.length ? theirs[i] : null,
          mine: i < mine.length ? mine[i] : null,
        ),
  ];
}

/// Quick reactions offered under a moment (mirrors the DB check).
const momentEmojis = ['❤️', '😂', '😮', '😢', '🔥', '🤲'];

/// An emoji reaction or a short comment on a moment.
class MomentReply {
  const MomentReply({
    required this.id,
    required this.momentId,
    required this.authorId,
    required this.createdAt,
    this.emoji,
    this.body,
  });

  factory MomentReply.fromRow(Map<String, dynamic> r) => MomentReply(
    id: r['id'] as String,
    momentId: r['moment_id'] as String,
    authorId: r['author_id'] as String,
    emoji: r['emoji'] as String?,
    body: r['body'] as String?,
    createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
  );

  final String id;
  final String momentId;
  final String authorId;
  final String? emoji;
  final String? body;
  final DateTime createdAt;
}

/// Longest clip the camera records.
const maxMomentVideo = Duration(seconds: 3);
const maxMomentCaption = 120;
