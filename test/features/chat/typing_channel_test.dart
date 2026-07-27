import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/data/typing_channel.dart';

void main() {
  test('debouncer emits true once then false after the quiet window', () {
    fakeAsync((async) {
      final events = <bool>[];
      final d = TypingDebouncer(quiet: const Duration(seconds: 3), emit: events.add);
      d.onKeystroke();
      d.onKeystroke();
      expect(events, [true]); // only one true despite two keystrokes
      async.elapse(const Duration(seconds: 3));
      expect(events, [true, false]);
    });
  });

  test('a keystroke mid-window resets the quiet timer', () {
    fakeAsync((async) {
      final events = <bool>[];
      final d = TypingDebouncer(quiet: const Duration(seconds: 3), emit: events.add);
      d.onKeystroke(); // true
      async.elapse(const Duration(seconds: 2)); // still within window
      expect(events, [true]);
      d.onKeystroke(); // resets the 3s timer; no new true
      async.elapse(const Duration(seconds: 2)); // 2s after the 2nd keystroke -> still typing
      expect(events, [true],
          reason: 'timer must have reset; false not emitted yet');
      async.elapse(const Duration(seconds: 1)); // now 3s quiet since last keystroke
      expect(events, [true, false]);
    });
  });
}
