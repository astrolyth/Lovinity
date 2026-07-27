import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/prayer_log/domain/prayer_log_providers.dart';

void main() {
  test('only today and yesterday are loggable', () {
    final now = DateTime(2026, 7, 15, 10);
    expect(isLoggableDate(DateTime(2026, 7, 15), now: now), isTrue);
    expect(isLoggableDate(DateTime(2026, 7, 14), now: now), isTrue);
    expect(isLoggableDate(DateTime(2026, 7, 13), now: now), isFalse);
    expect(isLoggableDate(DateTime(2026, 7, 16), now: now), isFalse);
  });
}
