// lib/features/chat/data/typing_channel.dart
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Pure, timer-based debounce/dedup logic for typing presence.
///
/// [onKeystroke] emits `true` once immediately on the first keystroke of a
/// burst, then schedules `false` to fire after [quiet] elapses with no
/// further keystroke. Repeated keystrokes within the quiet window reset the
/// timer but do not re-emit `true`.
class TypingDebouncer {
  TypingDebouncer({required this.quiet, required this.emit});

  final Duration quiet;
  final void Function(bool typing) emit;

  Timer? _timer;
  bool _typing = false;

  void onKeystroke() {
    if (!_typing) {
      _typing = true;
      emit(true);
    }
    _timer?.cancel();
    _timer = Timer(quiet, () {
      _typing = false;
      emit(false);
    });
  }

  /// Cancels any pending timer without emitting. Call on dispose.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Thin wrapper over a Supabase Realtime broadcast channel used to convey
/// ephemeral typing presence between spouses. Typing state is never stored
/// or encrypted — it leaks only "someone is typing", which is negligible.
class TypingChannel {
  TypingChannel({
    required SupabaseClient supabase,
    required String conversationId,
    Duration quiet = const Duration(seconds: 3),
  }) : _channel = supabase.channel('chat:$conversationId') {
    _debouncer = TypingDebouncer(quiet: quiet, emit: _sendTyping);
    _channel
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final typing = payload['typing'] == true;
            if (!_spouseTypingController.isClosed) {
              _spouseTypingController.add(typing);
            }
          },
        )
        .subscribe();
  }

  final RealtimeChannel _channel;
  late final TypingDebouncer _debouncer;
  final _spouseTypingController = StreamController<bool>.broadcast();

  /// Emits the spouse's typing state as received over the broadcast channel.
  Stream<bool> get spouseTyping => _spouseTypingController.stream;

  /// Call on every composer keystroke; debounced/deduped internally.
  void onKeystroke() => _debouncer.onKeystroke();

  void _sendTyping(bool typing) {
    _channel.sendBroadcastMessage(
      event: 'typing',
      payload: {'typing': typing},
    );
  }

  Future<void> dispose() async {
    _debouncer.dispose();
    await _spouseTypingController.close();
    await _channel.unsubscribe();
  }
}
