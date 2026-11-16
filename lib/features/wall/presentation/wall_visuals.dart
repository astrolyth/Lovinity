import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../domain/wall_models.dart';

String wallHeroTag(String itemId) => 'wall-thumb-$itemId';

/// Source-tinted gradient, used as the placeholder behind every preview so a
/// missing or expired image still looks intentional.
LinearGradient wallSourceGradient(WallSource source) {
  final colors = switch (source) {
    WallSource.youtube => const [Color(0xFF3B2A12), Color(0xFFC9883A), Color(0xFFF2C14E)],
    WallSource.instagram => const [Color(0xFF2B1020), Color(0xFF8A3A5C), Color(0xFFE0A3B8)],
    WallSource.tiktok => const [Color(0xFF0F1A24), Color(0xFF2D6E7E), Color(0xFF8FD3D9)],
    WallSource.article => const [Color(0xFF10243A), Color(0xFF2F5D8A), Color(0xFF8FB7D9)],
    WallSource.note => const [Color(0xFF241A3A), Color(0xFF5A4A9A), Color(0xFFB8A8F0)],
    WallSource.photo || WallSource.video => const [Color(0xFF2A1A1A), Color(0xFF8A4A3A), Color(0xFFE0B09F)],
  };
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: colors,
    stops: const [0, 0.6, 1],
  );
}

IconData wallSourceIcon(WallSource source) => switch (source) {
      WallSource.youtube => Icons.smart_display_rounded,
      WallSource.instagram => Icons.camera_alt_rounded,
      WallSource.tiktok => Icons.music_note_rounded,
      WallSource.article => Icons.article_rounded,
      WallSource.note => Icons.sticky_note_2_rounded,
      WallSource.photo => Icons.photo_rounded,
      WallSource.video => Icons.videocam_rounded,
    };

class WallThumbnail extends StatelessWidget {
  const WallThumbnail({
    super.key,
    required this.source,
    this.imageUrl,
    this.height,
    this.borderRadius = 0,
    this.showSourcePill = true,
    this.showPlay = true,
  });

  final WallSource source;
  final String? imageUrl;
  final double? height;
  final double borderRadius;
  final bool showSourcePill;
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final play = showPlay && source.isVideo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(gradient: wallSourceGradient(source)),
              child: play
                  ? null
                  : Center(
                      child: Icon(wallSourceIcon(source),
                          size: 28, color: Colors.white.withValues(alpha: 0.35)),
                    ),
            ),
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, wasSync) => wasSync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: LovMotion.standard,
                        child: child,
                      ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            if (play)
              Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                ),
              ),
            if (showSourcePill)
              Positioned(top: 8, left: 8, child: _SourcePill(source: source)),
          ],
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source});
  final WallSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(LovRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(wallSourceIcon(source), size: 11, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            source.label,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The sharer's note, shown as a quote with a gold rule.
class WallNoteQuote extends StatelessWidget {
  const WallNoteQuote({super.key, required this.text, this.maxLines, this.large = false});

  final String text;
  final int? maxLines;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary, width: 2)),
      ),
      child: Text(
        text.trim(),
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: large
            ? theme.textTheme.titleMedium
            : theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.85)),
      ),
    );
  }
}

/// Gold-when-selected pill used for collection filters and pickers.
class WallPill extends StatelessWidget {
  const WallPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LovRadius.pill),
          child: AnimatedContainer(
            duration: LovMotion.standard,
            curve: LovMotion.standardCurve,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : scheme.surface,
              borderRadius: BorderRadius.circular(LovRadius.pill),
              border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WallAvatar extends StatelessWidget {
  const WallAvatar({super.key, required this.name, required this.isSelf, this.size = 28});

  final String name;
  final bool isSelf;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelf ? scheme.primary : const Color(0xFF8A3A5C),
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
          color: isSelf ? scheme.onPrimary : Colors.white,
        ),
      ),
    );
  }
}

class WallUnseenDot extends StatelessWidget {
  const WallUnseenDot({super.key = const Key('wall-unseen-dot')});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary,
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 6),
        ],
      ),
    );
  }
}

/// Opens [url] in its own app (YouTube, Instagram…) or the browser.
Future<void> openWallLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    messenger?.showSnackBar(const SnackBar(content: Text("Couldn't open that link")));
  }
}
