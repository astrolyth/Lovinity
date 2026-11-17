import 'dart:async';

/// Counts taps locally and saves them in batches. A failed save puts the
/// count back so nothing is lost.
class TapBatcher {
  TapBatcher({required this.flushEvery, required this.save});

  final Duration flushEvery;
  final Future<void> Function(int count) save;

  int _pending = 0;
  Timer? _timer;
  bool _disposed = false;

  int get pending => _pending;

  void tap() {
    _pending++;
    _arm();
  }

  void _arm() {
    if (_disposed || _timer != null) return;
    _timer = Timer(flushEvery, () {
      _timer = null;
      flushNow().whenComplete(() {
        if (_pending > 0) _arm();
      });
    });
  }

  Future<void> flushNow() async {
    if (_pending == 0) return;
    // Take-and-zero before awaiting so concurrent flushes never double-save.
    final n = _pending;
    _pending = 0;
    try {
      await save(n);
    } catch (_) {
      _pending += n;
      _arm(); // keep retrying even if nobody taps again
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
