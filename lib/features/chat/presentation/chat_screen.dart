import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crypto/crypto_providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../home/domain/home_providers.dart';
import '../../auth/domain/auth_controller.dart';
import '../../duas/domain/dua_library_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../wall/domain/wall_models.dart';
import '../../wall/domain/wall_providers.dart';
import '../domain/chat_providers.dart';
import '../domain/chat_service.dart';
import 'media_picker.dart';
import 'message_bubble.dart';
import 'voice_note.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  String? _replyToMessageId;
  String? _replyPreview;
  bool _showEmojiPicker = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Also mounted app-wide in home_screen.dart so syncing/decrypting keeps
    // working while chat isn't open (e.g. a push wakes the app). Watching
    // these plain (non-autoDispose) providers here too is redundant, not
    // duplicative: Riverpod resolves both watches to the same single
    // instance/subscription, so this is just belt-and-suspenders for the
    // case chat is reached without home ever having built.
    ref.watch(inboxPumpProvider);
    ref.watch(receiptPumpProvider);

    // Mark incoming messages read whenever the conversation changes while this
    // screen is open — i.e. on open and on each new message. Clears the unread
    // badge and sends the "read" receipt to the spouse. No-op when nothing is
    // unread or the service isn't ready.
    ref.listen(conversationMessagesProvider, (_, next) {
      if (next.hasValue) {
        ref.read(chatServiceProvider).asData?.value?.markConversationRead();
      }
    });

    final theme = Theme.of(context);
    final myId = ref.watch(authSessionProvider).asData?.value?.user.id;
    final messagesAsync = ref.watch(conversationMessagesProvider);
    final chatServiceAsync = ref.watch(chatServiceProvider);
    final chatService = chatServiceAsync.asData?.value;
    final ready = chatService != null;
    final setupError = chatServiceAsync.hasError;
    final typingChannel = ref.watch(typingChannelProvider);
    final spouseTyping = ref.watch(spouseTypingProvider).asData?.value ?? false;

    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName.trim() ??
        '';
    return Scaffold(
      backgroundColor: context.lov.bg,
      body: Column(
        children: [
          _ChatHeader(name: spouseName.isEmpty ? 'Your spouse' : spouseName),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load messages',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(LovSpace.xl),
                      child: Text(
                        'Say salam to start the conversation',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  );
                }
                // Newest at the bottom: reverse the asc-ordered list and feed
                // a reversed ListView so it renders bottom-up.
                final newestFirst = messages.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
                  itemCount: newestFirst.length,
                  itemBuilder: (context, index) {
                    final message = newestFirst[index];
                    return MessageBubble(
                      message: message,
                      isOwn: myId != null && message.senderId == myId,
                      onReact: (emoji) {
                        ref
                            .read(chatServiceProvider)
                            .value
                            ?.sendReaction(
                              targetMessageId: message.id,
                              emoji: emoji,
                              add: true,
                            );
                      },
                      onReply: () {
                        setState(() {
                          _replyToMessageId = message.id;
                          _replyPreview = (message.body ?? '').isEmpty
                              ? 'a message'
                              : message.body;
                        });
                      },
                      onDownloadAttachment: (id) => ref
                          .read(chatServiceProvider)
                          .value
                          ?.downloadAttachment(id),
                      onSaveToWall: () => _saveToWall(message.body ?? ''),
                      onDeleteForMe: myId == null
                          ? null
                          : () {
                              ref
                                  .read(chatStoreProvider(myId))
                                  .deleteMessage(message.id)
                                  .then(
                                    (_) {
                                      if (context.mounted) {
                                        showLovToast(context, 'Deleted for you');
                                      }
                                    },
                                    onError: (Object _) {
                                      if (context.mounted) {
                                        showLovToast(
                                          context,
                                          "Couldn't delete",
                                          icon: Icons.error_outline_rounded,
                                        );
                                      }
                                    },
                                  );
                            },
                    );
                  },
                );
              },
            ),
          ),
          if (_replyToMessageId != null)
            _ReplyBanner(
              preview: _replyPreview ?? '',
              onCancel: () => setState(() {
                _replyToMessageId = null;
                _replyPreview = null;
              }),
            ),
          if (!ready)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LovSpace.lg,
                vertical: LovSpace.xs,
              ),
              child: setupError
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Couldn't set up secure chat. Check your "
                            'connection and try again.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(signalSessionServiceProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : Text(
                      'Setting up secure chat…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
            ),
          if (spouseTyping)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _TypingBubble(),
              ),
            ),
          if (_showEmojiPicker)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) => _insertEmoji(emoji.emoji),
              ),
            ),
          _Composer(
            controller: _controller,
            enabled: ready,
            onChanged: (_) => typingChannel?.onKeystroke(),
            onSend: () => _send(chatService),
            onAttach: _showAttachSheet,
            onToggleEmoji: _toggleEmojiPicker,
          ),
        ],
      ),
    );
  }

  /// "Save to wall": the message text becomes a note on the couple's Wall.
  Future<void> _saveToWall(String text) async {
    final self = ref.read(authSessionProvider).asData?.value?.user.id;
    final coupleId = ref.read(currentCoupleProvider).asData?.value?.id;
    if (text.trim().isEmpty || self == null || coupleId == null) return;
    try {
      await ref
          .read(wallRepositoryProvider)
          .addItem(
            coupleId: coupleId,
            userId: self,
            source: WallSource.note,
            note: text.trim(),
          );
      if (mounted) showLovToast(context, 'Pinned to your wall');
    } catch (_) {
      if (mounted) {
        showLovToast(
          context,
          "Couldn't save to the wall",
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  /// Records, sends encrypted, then deletes the temporary recording.
  Future<void> _sendVoiceNote() async {
    final rec = await recordVoiceNote(context);
    if (rec == null) return;
    final (file, length) = rec;
    final service = ref.read(chatServiceProvider).value;
    try {
      if (service != null) {
        final replyTo = _replyToMessageId;
        setState(() {
          _replyToMessageId = null;
          _replyPreview = null;
        });
        await service.sendVoiceNote(
          bytes: await file.readAsBytes(),
          durationMs: length.inMilliseconds,
          replyToMessageId: replyTo,
        );
      }
    } finally {
      unawaited(file.delete().then((_) {}, onError: (_) {}));
    }
  }

  /// "Dua": pick one from the library and send it as an encrypted message.
  void _pickDua() {
    showLovSheet<void>(
      context,
      title: 'Send a dua',
      builder: (sheet) => Consumer(
        builder: (sheet, ref, _) {
          final duas = ref.watch(duaLibraryProvider);
          return duas.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text("Couldn't load duas"),
            ),
            data: (list) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheet).height * .6,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final d in list)
                    LovSheetRow(
                      icon: Icons.menu_book_outlined,
                      title: d.title,
                      subtitle: d.reference,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        final service = ref.read(chatServiceProvider).value;
                        if (service == null) return;
                        unawaited(
                          service.sendText(
                            [
                              '🤲 ${d.arabic}',
                              d.translation,
                              if (d.reference != null) '(${d.reference})',
                            ].join('\n'),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _send(ChatService? service) {
    final text = _controller.text.trim();
    if (text.isEmpty || service == null) return;
    final replyToMessageId = _replyToMessageId;
    // Fire-and-forget: sendText handles its own failure by marking the row
    // 'failed'; we must not leave an unhandled async error.
    unawaited(service.sendText(text, replyToMessageId: replyToMessageId));
    _controller.clear();
    setState(() {
      _replyToMessageId = null;
      _replyPreview = null;
    });
  }

  /// Whatever is typed in the composer becomes the attachment's caption, and a
  /// pending reply is carried through — same contract as [_send]. Both are
  /// cleared afterwards so the banner/text can't linger and get reattached to
  /// the next message.
  Future<void> _attachPhoto(MediaSource source) async {
    final photo = await ref.read(mediaPickerProvider).pickPhoto(source);
    if (photo == null) return;
    final service = ref.read(chatServiceProvider).value;
    if (service == null) return;
    final caption = _controller.text.trim();
    final replyToMessageId = _replyToMessageId;
    unawaited(
      service.sendPhoto(
        bytes: photo.bytes,
        mimeType: photo.mimeType,
        width: photo.width,
        height: photo.height,
        thumbnailBytes: photo.thumbnailBytes,
        caption: caption.isEmpty ? null : caption,
        replyToMessageId: replyToMessageId,
      ),
    );
    _controller.clear();
    setState(() {
      _replyToMessageId = null;
      _replyPreview = null;
    });
  }

  Future<void> _attachVideo(MediaSource source) async {
    final PickedVideo? video;
    try {
      video = await ref.read(mediaPickerProvider).pickVideo(source);
    } on MediaRejected catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (video == null || !mounted) return;
    final service = ref.read(chatServiceProvider).value;
    if (service == null) return;
    final caption = _controller.text.trim();
    final replyToMessageId = _replyToMessageId;
    unawaited(
      service.sendVideo(
        bytes: video.bytes,
        mimeType: video.mimeType,
        durationMs: video.durationMs,
        thumbnailBytes: video.thumbnailBytes,
        caption: caption.isEmpty ? null : caption,
        replyToMessageId: replyToMessageId,
      ),
    );
    _controller.clear();
    setState(() {
      _replyToMessageId = null;
      _replyPreview = null;
    });
  }

  void _showAttachSheet() {
    showLovSheet<void>(
      context,
      title: 'Share',
      builder: (sheet) {
        void go(VoidCallback f) {
          Navigator.of(sheet).pop();
          f();
        }

        final tiles = <(IconData, String, VoidCallback)>[
          (
            Icons.photo_camera_outlined,
            'Take Photo',
            () => _attachPhoto(MediaSource.camera),
          ),
          (
            Icons.photo_library_outlined,
            'Photo Library',
            () => _attachPhoto(MediaSource.gallery),
          ),
          (
            Icons.videocam_outlined,
            'Video',
            () => _attachVideo(MediaSource.gallery),
          ),
          (Icons.mic_none_rounded, 'Voice note', _sendVoiceNote),
          (Icons.menu_book_outlined, 'Dua', _pickDua),
          (
            Icons.mail_outline_rounded,
            'Letter',
            () => context.push('/home/letters'),
          ),
          (
            Icons.camera_rounded,
            'Moment',
            () => context.push('/moments/camera'),
          ),
        ];
        final p = context.lov;
        return Column(
          children: [
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 96,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final (i, (icon, label, f)) in tiles.indexed)
                  LovRise(
                    delay: Duration(milliseconds: 30 * i),
                    offset: const Offset(0, 12),
                    child: LovPressable(
                      onTap: () => go(f),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: p.line),
                          color: p.hi.withValues(alpha: .04),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: p.accent.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(icon, color: p.accent, size: 20),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Everything you send is end-to-end encrypted.',
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ],
        );
      },
    );
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final newText = text.replaceRange(start, end, emoji);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: start + emoji.length,
    );
  }
}

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.preview, required this.onCancel});

  final String preview;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        LovSpace.lg,
        0,
        LovSpace.lg,
        LovSpace.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.md,
        vertical: LovSpace.sm,
      ),
      decoration: BoxDecoration(
        color: context.lov.hi.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onAttach,
    required this.onToggleEmoji,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onToggleEmoji;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.surface2)),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          LovIconButton(
            icon: Icons.attach_file,
            label: 'Attach',
            onTap: enabled ? onAttach : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.only(left: 16, right: 4),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: p.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onChanged: onChanged,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: enabled
                            ? 'Message'
                            : 'Setting up secure chat…',
                        filled: false,
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, v, _) {
                      final canSend = enabled && v.text.trim().isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, a) => ScaleTransition(
                            scale: CurvedAnimation(parent: a, curve: lovBounce),
                            child: child,
                          ),
                          child: canSend
                              ? IconButton(
                                  key: const ValueKey('send'),
                                  tooltip: 'Send',
                                  onPressed: onSend,
                                  style: IconButton.styleFrom(
                                    backgroundColor: p.accent,
                                    foregroundColor: p.onAccent,
                                    minimumSize: const Size(36, 36),
                                    fixedSize: const Size(36, 36),
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 20,
                                  ),
                                )
                              : IconButton(
                                  key: const ValueKey('emoji'),
                                  tooltip: 'Emoji',
                                  onPressed: enabled ? onToggleEmoji : null,
                                  color: p.muted,
                                  icon: const Icon(
                                    Icons.emoji_emotions_outlined,
                                    size: 22,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spouse avatar, name and the encryption note above the thread.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 10,
        12,
        12,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.surface2)),
      ),
      child: Row(
        children: [
          LovIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            label: 'Back',
            onTap: () => context.canPop() ? context.pop() : context.go('/home'),
          ),
          const SizedBox(width: 12),
          LovAvatar(initial: name, size: 40, partner: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 12, color: p.muted),
                    const SizedBox(width: 4),
                    Text(
                      'End-to-end encrypted',
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          LovIconButton(
            icon: Icons.photo_library_outlined,
            label: 'Shared moments',
            onTap: () => context.go('/moments'),
          ),
        ],
      ),
    );
  }
}

/// Three rose dots bouncing in a bubble while your spouse types.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Semantics(
      label: 'Your spouse is typing',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Builder(
                  builder: (_) {
                    final t = ((_c.value - i * .125) % 1 + 1) % 1;
                    final up = t < .3
                        ? t / .3
                        : (t < .6 ? 1 - (t - .3) / .3 : 0);
                    return Transform.translate(
                      offset: Offset(0, -4.0 * up),
                      child: Opacity(
                        opacity: .5 + .5 * up,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: p.partner,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
