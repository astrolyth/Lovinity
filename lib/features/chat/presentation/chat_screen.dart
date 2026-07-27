import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/crypto_providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../domain/chat_providers.dart';
import '../domain/chat_service.dart';
import 'message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  String? _replyToMessageId;
  String? _replyPreview;

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

    return LovScaffold(
      title: 'Chat',
      padded: false,
      child: Column(
        children: [
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
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
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
                  padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
                  itemCount: newestFirst.length,
                  itemBuilder: (context, index) {
                    final message = newestFirst[index];
                    return MessageBubble(
                      message: message,
                      isOwn: myId != null && message.senderId == myId,
                      onReact: (emoji) {
                        ref.read(chatServiceProvider).value?.sendReaction(
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
                          onPressed: () => ref
                              .invalidate(signalSessionServiceProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : Text(
                      'Setting up secure chat…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
            ),
          if (spouseTyping)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LovSpace.lg,
                vertical: LovSpace.xs,
              ),
              child: Text(
                'typing…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          _Composer(
            controller: _controller,
            enabled: ready,
            onChanged: (_) => typingChannel?.onKeystroke(),
            onSend: () => _send(chatService),
          ),
        ],
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
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LovRadius.sm),
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
    this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LovSpace.lg,
        LovSpace.xs,
        LovSpace.lg,
        LovSpace.lg,
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
              decoration: InputDecoration(
                hintText: enabled ? 'Message…' : 'Setting up secure chat…',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: LovSpace.lg,
                  vertical: LovSpace.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LovRadius.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: LovSpace.sm),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
