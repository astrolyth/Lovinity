import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/notifications/activity_detectors.dart';

void main() {
  group('newRowDetector', () {
    test('never fires on the first emission (existing history, not new activity)', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a', 'b']);
      expect(fired, isEmpty);
    });

    test('fires only for keys new since the previous emission', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a', 'b']); // baseline, no fire
      detector(['a', 'b', 'c']); // c is new
      expect(fired, ['c']);
    });

    test('a removed-then-readded key fires again', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a']);
      detector([]); // a removed
      detector(['a']); // a reappears
      expect(fired, ['a']);
    });

    test('unrelated churn with no new keys does not fire', () {
      final fired = <String>[];
      final detector = newRowDetector<String>(
        keyOf: (s) => s,
        onNew: fired.add,
      );
      detector(['a', 'b']);
      detector(['b', 'a']); // same set, different order
      expect(fired, isEmpty);
    });
  });

  group('pairingJustActivated', () {
    test('null -> active is a fresh pairing', () {
      expect(pairingJustActivated(null, 'active'), isTrue);
    });

    test('pending -> active is a fresh pairing', () {
      expect(pairingJustActivated('pending', 'active'), isTrue);
    });

    test('active -> active does not refire', () {
      expect(pairingJustActivated('active', 'active'), isFalse);
    });

    test('active -> null does not fire', () {
      expect(pairingJustActivated('active', null), isFalse);
    });

    test('null -> null does not fire', () {
      expect(pairingJustActivated(null, null), isFalse);
    });
  });
}
