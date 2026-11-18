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

/// Groups newest-first moments by local calendar day, keeping order.
List<(DateTime, List<Moment>)> groupByDay(List<Moment> moments) {
  final out = <(DateTime, List<Moment>)>[];
  for (final m in moments) {
    final d = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
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

/// Longest clip the camera records.
const maxMomentVideo = Duration(seconds: 3);
const maxMomentCaption = 120;
