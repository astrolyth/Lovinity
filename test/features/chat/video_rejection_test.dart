import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/chat/presentation/media_picker.dart';

void main() {
  test('accepts a video at both limits', () {
    expect(videoRejection(bytes: maxVideoBytes, durationMs: maxVideoMs), isNull);
  });

  test('rejects a video over 60 s', () {
    expect(
      videoRejection(bytes: 1, durationMs: maxVideoMs + 1),
      'Videos can be up to 60 seconds',
    );
  });

  test('rejects a video over 50 MiB', () {
    expect(
      videoRejection(bytes: maxVideoBytes + 1, durationMs: 1000),
      contains('too large (max 50 MB)'),
    );
  });
}
