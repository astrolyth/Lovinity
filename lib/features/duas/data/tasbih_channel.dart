import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Live tap deltas + presence between spouses for one couple's tasbih room.
/// Ephemeral only; durable counts go through [TasbihRepository].
class TasbihChannel {
  TasbihChannel({
    required SupabaseClient supabase,
    required String coupleId,
    required this.selfId,
    required this.counterId,
    this.throttle = const Duration(milliseconds: 250),
  }) : _channel = supabase.channel('tasbih:$coupleId') {
    _channel
        .onBroadcast(
          event: 'tap',
          callback: (p) {
            if (p['user_id'] == selfId || p['counter_id'] != counterId) return;
            final d = (p['delta'] as num?)?.toInt() ?? 0;
            if (d > 0 && !_deltas.isClosed) _deltas.add(d);
          },
        )
        .onPresenceSync((_) {
          final here = _channel.presenceState().any(
                (s) => s.presences.any((p) => p.payload['user_id'] != selfId),
              );
          if (!_here.isClosed) _here.add(here);
        })
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            _channel.track({'user_id': selfId});
          }
        });
  }

  final String selfId;
  final String counterId;
  final Duration throttle;
  final RealtimeChannel _channel;
  final _deltas = StreamController<int>.broadcast();
  final _here = StreamController<bool>.broadcast();
  int _acc = 0;
  Timer? _cooldown;

  Stream<int> get spouseDeltas => _deltas.stream;
  Stream<bool> get spouseHere => _here.stream;

  /// First tap after idle sends now; later taps are batched into one trailing
  /// send per [throttle].
  void tap() {
    _acc++;
    if (_cooldown == null) _send();
  }

  void _send() {
    if (_acc == 0) {
      _cooldown = null;
      return;
    }
    final n = _acc;
    _acc = 0;
    _channel.sendBroadcastMessage(
      event: 'tap',
      payload: {'user_id': selfId, 'counter_id': counterId, 'delta': n},
    );
    _cooldown = Timer(throttle, () {
      _cooldown = null;
      if (_acc > 0) _send();
    });
  }

  Future<void> dispose() async {
    _cooldown?.cancel();
    _cooldown = null;
    if (_acc > 0) {
      final n = _acc;
      _acc = 0;
      _channel.sendBroadcastMessage(
        event: 'tap',
        payload: {'user_id': selfId, 'counter_id': counterId, 'delta': n},
      );
    }
    await _deltas.close();
    await _here.close();
    await _channel.untrack();
    await _channel.unsubscribe();
  }
}
