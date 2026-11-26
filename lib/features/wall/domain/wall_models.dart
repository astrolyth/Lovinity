import 'package:flutter/foundation.dart';

/// Optional shelf a Wall item is filed under. [key] is the DB value.
enum WallCollection {
  recipes('Recipes'),
  places('Places'),
  home('Home'),
  funny('Funny'),
  deen('Deen');

  const WallCollection(this.label);
  final String label;
  String get key => name;

  static WallCollection? fromKey(String? key) {
    for (final c in values) {
      if (c.key == key) return c;
    }
    return null;
  }
}

/// Where a Wall item came from. [key] is the DB value.
enum WallSource {
  youtube('YouTube', isVideo: true),
  instagram('Instagram', isVideo: true),
  tiktok('TikTok', isVideo: true),
  article('Article'),
  note('Note'),
  photo('Photo'),
  video('Video', isVideo: true);

  const WallSource(this.label, {this.isVideo = false});
  final String label;
  final bool isVideo;
  String get key => name;

  static WallSource? fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// The six Wall reactions, in display order. [key] is the DB value.
enum WallReactionKind {
  heart('🤍'),
  laugh('😂'),
  fire('🔥'),
  dua('🤲'),
  wow('😮'),
  star('⭐');

  const WallReactionKind(this.emoji);
  final String emoji;
  String get key => name;

  static WallReactionKind? fromKey(String? key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }
}

/// Host of [url] without a leading `www.`, or null if it has no host.
String? domainOf(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

@immutable
class WallItem {
  const WallItem({
    required this.id,
    required this.coupleId,
    required this.addedBy,
    required this.source,
    required this.isPinned,
    required this.createdAt,
    this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.collection,
    this.note,
    this.mediaPath,
    this.mediaMime,
  });

  final String id;
  final String coupleId;
  final String addedBy;
  final String? url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final WallSource source;
  final WallCollection? collection;
  final String? note;
  final String? mediaPath;
  final String? mediaMime;
  final bool isPinned;
  final DateTime createdAt;

  factory WallItem.fromRow(Map<String, dynamic> row) {
    final url = row['url'] as String?;
    return WallItem(
      id: row['id'] as String,
      coupleId: row['couple_id'] as String,
      addedBy: row['added_by'] as String,
      url: url,
      title: row['title'] as String?,
      description: row['description'] as String?,
      imageUrl: row['image_url'] as String?,
      source:
          WallSource.fromKey(row['source'] as String?) ??
          (url == null ? WallSource.note : WallSource.article),
      collection: WallCollection.fromKey(row['collection'] as String?),
      note: row['note'] as String?,
      mediaPath: row['media_url'] as String?,
      mediaMime: row['media_mime'] as String?,
      isPinned: row['is_pinned'] as bool? ?? false,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }

  bool get hasMedia => mediaPath != null;

  /// Storage path of the preview image: the poster for videos, the file itself for photos.
  String? get thumbPath {
    final p = mediaPath;
    if (p == null) return null;
    if (source != WallSource.video) return p;
    return '${p.substring(0, p.lastIndexOf('/'))}/thumb.jpg';
  }

  /// e.g. `youtube.com`; null for notes.
  String? get domain => url == null ? null : domainOf(url!);

  /// The preview title, else the domain, else the note text.
  String get displayTitle {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    return domain ?? note?.trim() ?? '';
  }
}

@immutable
class WallReaction {
  const WallReaction({
    required this.itemId,
    required this.userId,
    required this.kind,
  });

  final String itemId;
  final String userId;
  final WallReactionKind kind;

  /// Null for reaction keys this app version doesn't know.
  static WallReaction? tryFromRow(Map<String, dynamic> row) {
    final kind = WallReactionKind.fromKey(row['reaction'] as String?);
    if (kind == null) return null;
    return WallReaction(
      itemId: row['item_id'] as String,
      userId: row['user_id'] as String,
      kind: kind,
    );
  }
}

@immutable
class WallComment {
  const WallComment({
    required this.id,
    required this.itemId,
    required this.authorId,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String itemId;
  final String authorId;
  final String body;
  final DateTime createdAt;

  factory WallComment.fromRow(Map<String, dynamic> row) => WallComment(
    id: row['id'] as String,
    itemId: row['item_id'] as String,
    authorId: row['author_id'] as String,
    body: row['body'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
  );
}

/// How many of one reaction an item has, and whether one of them is mine.
@immutable
class ReactionCount {
  const ReactionCount({
    required this.kind,
    required this.count,
    required this.mine,
  });

  final WallReactionKind kind;
  final int count;
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is ReactionCount &&
      other.kind == kind &&
      other.count == count &&
      other.mine == mine;

  @override
  int get hashCode => Object.hash(kind, count, mine);

  @override
  String toString() => 'ReactionCount(${kind.key}, $count, mine: $mine)';
}
