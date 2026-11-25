import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/lov_kit.dart';
import '../data/chat_store.dart';
import 'photo_viewer_screen.dart';
import 'video_viewer_screen.dart';
import 'voice_note.dart';

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
    this.onSaveToWall,
    this.onDeleteForMe,
  });

  final ChatMessageRow message;
  final bool isOwn;
  final ValueChanged<String> onReact;
  final VoidCallback onReply;
  final ValueChanged<String> onDownloadAttachment;
  final VoidCallback? onSaveToWall;
  final VoidCallback? onDeleteForMe;

  static const _reactionEmojis = ['❤️', '🤲', '😂', '😮', '🥹', '👍'];

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final bg = isOwn ? p.accentSoft : p.surface2;
    final fg = isOwn ? p.accentInk : p.text;
    const r = Radius.circular(20);
    const tail = Radius.circular(6);

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActions(context),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.76,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: r,
              topRight: r,
              bottomLeft: isOwn ? r : tail,
              bottomRight: isOwn ? tail : r,
            ),
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
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Replying to a message',
                      style: TextStyle(fontSize: 13, color: p.text2),
                    ),
                  ),
                ),
              if (message.attachmentKind == 'audio')
                VoiceNotePlayer(
                  path: message.downloadStatus == 'downloaded'
                      ? message.localMediaPath
                      : null,
                  durationMs: message.durationMs,
                  color: fg,
                  downloading: message.downloadStatus == 'downloading',
                  onDownload: () => onDownloadAttachment(message.id),
                )
              else if (message.attachmentKind != null)
                _AttachmentContent(
                  message: message,
                  onDownloadAttachment: onDownloadAttachment,
                ),
              if (message.attachmentKind == null)
                Text(
                  message.body ?? '',
                  style: TextStyle(fontSize: 15, height: 1.4, color: fg),
                )
              else if (message.body != null && message.body!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LovSpace.xs),
                  child: Text(
                    message.body!,
                    style: TextStyle(fontSize: 15, height: 1.4, color: fg),
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
    HapticFeedback.selectionClick();
    final text = (message.body ?? '').trim();
    showLovSheet<void>(
      context,
      title: 'Message',
      builder: (sheet) {
        final p = sheet.lov;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (text.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(0, 6, 0, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: p.hi.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  text.length > 140 ? '${text.substring(0, 140)}…' : text,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ),
            Container(
              margin: const EdgeInsets.fromLTRB(0, 10, 0, 6),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: p.hi.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in _reactionEmojis)
                    Semantics(
                      button: true,
                      label: 'React $emoji',
                      child: LovPressable(
                        scale: .85,
                        onTap: () {
                          Navigator.of(sheet).pop();
                          onReact(emoji);
                        },
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Center(
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            LovSheetRow(
              icon: Icons.reply_rounded,
              title: 'Reply',
              onTap: () {
                Navigator.of(sheet).pop();
                onReply();
              },
            ),
            if (text.isNotEmpty)
              LovSheetRow(
                icon: Icons.copy_rounded,
                title: 'Copy',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.of(sheet).pop();
                  showLovToast(context, 'Copied');
                },
              ),
            if (text.isNotEmpty && onSaveToWall != null)
              LovSheetRow(
                icon: Icons.push_pin_outlined,
                title: 'Save to wall',
                onTap: () {
                  Navigator.of(sheet).pop();
                  onSaveToWall!();
                },
              ),
            if (onDeleteForMe != null)
              LovSheetRow(
                icon: Icons.delete_outline_rounded,
                title: 'Delete for me',
                danger: true,
                onTap: () {
                  Navigator.of(sheet).pop();
                  onDeleteForMe!();
                },
              ),
          ],
        );
      },
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
                      'MessageBubble: failed to decode thumbnail: $error',
                    );
                    return Container(color: Colors.black12);
                  },
                )
              else
                Container(color: Colors.black12),
              if (isVideo && status != 'downloading')
                const Icon(
                  Icons.play_circle_fill,
                  size: 48,
                  color: Colors.white,
                ),
              if (status == 'downloading') const CircularProgressIndicator(),
              if (status == 'failed')
                const Icon(
                  Icons.error_outline,
                  color: LovColors.error,
                  size: 32,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context) {
    if (message.downloadStatus == 'downloading') return;
    if (message.downloadStatus == 'downloaded' &&
        message.localMediaPath != null) {
      _openViewer(context, message.localMediaPath!);
      return;
    }
    onDownloadAttachment(message.id);
  }

  void _openViewer(BuildContext context, String path) {
    if (message.attachmentKind == 'video') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VideoViewerScreen(filePath: path)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PhotoViewerScreen(filePath: path)),
      );
    }
  }
}
