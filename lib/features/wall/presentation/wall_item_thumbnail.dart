import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wall_models.dart';
import '../domain/wall_providers.dart';
import 'wall_visuals.dart';

/// Preview of any wall item: a link's og:image, or a signed URL for media.
/// While the signed URL loads, or if it fails, shows the branded placeholder.
class WallItemThumbnail extends StatelessWidget {
  const WallItemThumbnail({
    super.key,
    required this.item,
    this.height,
    this.borderRadius = 0,
    this.showSourcePill = true,
    this.showPlay = true,
  });

  final WallItem item;
  final double? height;
  final double borderRadius;
  final bool showSourcePill;
  final bool showPlay;

  Widget _thumb(String? url) => WallThumbnail(
        source: item.source,
        imageUrl: url,
        height: height,
        borderRadius: borderRadius,
        showSourcePill: showSourcePill,
        showPlay: showPlay,
      );

  @override
  Widget build(BuildContext context) {
    final path = item.thumbPath;
    if (path == null) return _thumb(item.imageUrl);
    return Consumer(
      builder: (_, ref, _) =>
          _thumb(ref.watch(wallSignedUrlProvider(path)).asData?.value),
    );
  }
}
