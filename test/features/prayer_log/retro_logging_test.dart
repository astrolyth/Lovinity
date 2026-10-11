import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/prayer_log/domain/prayer_log_providers.dart';

void main() {
  // Loggability is expressed as an offset from "today" rather than an absolute
  // date, because "today" is not a single value for a couple split across two
  // timezones. The offset is always evaluated against the user's OWN zone —
  // you can only ever write your own rows, so a partner's clock has no bearing
  // on what you're allowed to correct.
  test('only today and yesterday are loggable', () {
    expect(isLoggableOffset(0), isTrue);
    expect(isLoggableOffset(1), isTrue);
    expect(isLoggableOffset(2), isFalse);
    expect(isLoggableOffset(30), isFalse);
  });

  test('a negative offset is not loggable', () {
    // The notifier clamps at 0, so this should be unreachable — but there is
    // no honest "tomorrow" to write into, so guard it here too.
    expect(isLoggableOffset(-1), isFalse);
  });
}
