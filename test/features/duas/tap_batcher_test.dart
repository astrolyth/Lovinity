// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/duas/domain/tap_batcher.dart';

void main() {
  const every = Duration(seconds: 5);

  test('3 taps then 5s saves 3 once', () {
    fakeAsync((async) {
      final saved = <int>[];
      final b = TapBatcher(flushEvery: every, save: (n) async => saved.add(n));
      b.tap();
      b.tap();
      b.tap();
      async.elapse(every);
      expect(saved, [3]);
      expect(b.pending, 0);
    });
  });

  test('failed save restores pending and later saves everything', () {
    fakeAsync((async) {
      final saved = <int>[];
      var fail = true;
      final b = TapBatcher(
        flushEvery: every,
        save: (n) async {
          if (fail) throw Exception('x');
          saved.add(n);
        },
      );
      b.tap();
      b.tap();
      b.tap();
      async.elapse(const Duration(seconds: 5));
      expect(b.pending, 3);
      fail = false;
      b.tap();
      b.flushNow();
      async.flushMicrotasks();
      expect(saved, [4]);
      expect(b.pending, 0);
    });
  });

  test('flushNow with nothing pending does not save', () {
    fakeAsync((async) {
      var calls = 0;
      final b = TapBatcher(flushEvery: every, save: (_) async => calls++);
      b.flushNow();
      async.flushMicrotasks();
      expect(calls, 0);
    });
  });

  test('concurrent flushNow does not double save', () {
    fakeAsync((async) {
      final saved = <int>[];
      final b = TapBatcher(flushEvery: every, save: (n) async => saved.add(n));
      b.tap();
      b.flushNow();
      b.flushNow();
      async.flushMicrotasks();
      expect(saved, [1]);
    });
  });

  test('dispose cancels the timer', () {
    fakeAsync((async) {
      var calls = 0;
      final b = TapBatcher(flushEvery: every, save: (_) async => calls++);
      b.tap();
      b.dispose();
      async.elapse(const Duration(seconds: 20));
      expect(calls, 0);
    });
  });
}
