import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../data/chat_store.dart';
import 'photo_viewer_screen.dart';
import 'video_viewer_screen.dart';

/// One chat bubble: aligns right for the current user, left for the spouse.
///
/// Long-press reveals a small action sheet: a quick-reaction emoji row
/// (calls [onReact]) and a "Reply" affordance (calls [onReply]).
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwn,
    required this.onReact,
    required this.onReply,
    required this.onDownloadAttachment,
  });

  final ChatMessageRow message;
  final bool isOwn;
  final ValueChanged<String> onReact;
  final VoidCallback onReply;
  final ValueChanged<String> onDownloadAttachment;

  static const _reactionEmojis = ['❤️', '👍', '😊'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = isOwn ? scheme.primary : scheme.surfaceContainerLow;
    final fg = isOwn ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: LovSpace.lg,
            vertical: LovSpace.xs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: LovSpace.md,
            vertical: LovSpace.sm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(LovRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.replyToMessageId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: LovSpace.xs),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LovSpace.sm,
                      vertical: LovSpace.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(LovRadius.xs),
                    ),
                    child: Text(
                      'Replying to a message',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              if (message.attachmentKind != null)
                _AttachmentContent(
                  message: message,
                  onDownloadAttachment: onDownloadAttachment,
                ),
              if (message.attachmentKind == null)
                Text(
                  message.body ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                )
              else if (message.body != null && message.body!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LovSpace.xs),
                  child: Text(
                    message.body!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
              if (isOwn) ...[
                const SizedBox(height: LovSpace.xxs),
                Align(
                  alignment: Alignment.centerRight,
                  child: _Receipt(message: message, baseColor: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: LovSpace.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final emoji in _reactionEmojis)
                    IconButton(
                      iconSize: 28,
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onReact(emoji);
                      },
                      icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply_outlined),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onReply();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a receipt tick for own messages, derived from [ChatMessageRow]
/// status/deliveredAt/readAt: ✓ sent, ✓✓ delivered, ✓✓ (tinted) read.
class _Receipt extends StatelessWidget {
  const _Receipt({required this.message, required this.baseColor});

  final ChatMessageRow message;
  final Color baseColor;

  static const _readTint = Color(0xFF4FC3F7);

  @override
  Widget build(BuildContext context) {
    final (label, color) = _derive();
    return Text(
      label,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    );
  }

  (String, Color) _derive() {
    if (message.status == 'failed') {
      return ('!', LovColors.error);
    }
    if (message.status == 'sending') {
      return ('🕓', baseColor.withValues(alpha: 0.6));
    }
    if (message.readAt != null || message.status == 'read') {
      return ('✓✓', _readTint);
    }
    if (message.deliveredAt != null || message.status == 'delivered') {
      return ('✓✓', baseColor.withValues(alpha: 0.7));
    }
    return ('✓', baseColor.withValues(alpha: 0.7));
  }
}

/// Renders one attachment message's media area: the embedded thumbnail is
/// always shown (no network needed); tap behavior depends on downloadStatus:
/// 'none'/'failed' triggers [onDownloadAttachment], 'downloading' is inert,
/// 'downloaded' opens a full-screen viewer.
class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({
    required this.message,
    required this.onDownloadAttachment,
  });

  final ChatMessageRow message;
  final ValueChanged<String> onDownloadAttachment;

  static const _size = 220.0;

  @override
  Widget build(BuildContext context) {
    final isVideo = message.attachmentKind == 'video';
    final thumb = message.thumbnailBytes;
    final status = message.downloadStatus;

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LovRadius.md),
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (thumb != null)
                Image.memory(
                  thumb,
                  fit: BoxFit.cover,
                  // Decrypted/synced thumbnail bytes could in principle be
                  // corrupt; fail soft with a placeholder rather than
                  // surfacing a framework error overlay.
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint(
                        'MessageBubble: failed to decode thumbnail: $error');
                    return Container(color: Colors.black12);
                  },
                )
              else
                Container(color: Colors.black12),
              if (isVideo && status != 'downloading')
                const Icon(Icons.play_circle_fill, size: 48, color: Colors.white),
              if (status == 'downloading') const CircularProgressIndicator(),
              if (status == 'failed')
                const Icon(Icons.error_outline, color: LovColors.error, size: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    if (message.downloadStatus == 'downloading') return;
    if (message.downloadStatus == 'downloaded' && message.localMediaPath != null) {
      _openViewer(context, message.localMediaPath!);
      return;
    }
    onDownloadAttachment(message.id);
  }

  void _openViewer(BuildContext context, String path) {
    if (message.attachmentKind == 'video') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => VideoViewerScreen(filePath: path)));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PhotoViewerScreen(filePath: path)));
    }
  }
}
