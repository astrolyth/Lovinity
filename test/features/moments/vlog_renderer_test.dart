import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/moments/data/vlog_renderer.dart';

void main() {
  const enc = ['-c:v', 'mpeg4'];

  test('empty half is a dark lavfi panel; photo loops; both are 3 s', () {
    final args = slotArgs(
      top: null,
      bottom: (path: '/t/me.jpg', isVideo: false),
      out: '/t/seg.mp4',
      encoder: enc,
    );
    final s = args.join(' ');
    expect(s, contains('-f lavfi -t 3.0 -i color=c=0x151515:s=720x640:r=30'));
    expect(s, contains('-loop 1 -t 3.0 -i /t/me.jpg'));
    expect(s, contains('vstack=inputs=2'));
    expect(args.last, '/t/seg.mp4');
    expect(s, contains('-an -c:v mpeg4'));
  });

  test('video half is trimmed and padded to the slot length', () {
    final s = slotArgs(
      top: (path: '/t/p.mp4', isVideo: true),
      bottom: (path: '/t/m.mp4', isVideo: true),
      out: '/t/o.mp4',
      encoder: enc,
    ).join(' ');
    expect(s, contains('-t 3.0 -i /t/p.mp4'));
    expect(s, isNot(contains('-loop')));
    expect(s, contains('tpad=stop_mode=clone:stop_duration=3.0'));
    expect(s, contains('trim=duration=3.0'));
  });

  test('concatList quotes paths, escaping single quotes', () {
    expect(
      concatList(['/a/seg_0.mp4', "/b/it's.mp4"]),
      "file '/a/seg_0.mp4'\nfile '/b/it'\\''s.mp4'",
    );
  });
}
