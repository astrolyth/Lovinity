import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/platform/share_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(ShareIntake.channelName);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('fromChannel keeps text + subject and rejects junk', () {
    final p = SharedPayload.fromChannel({'text': 'hi https://x.example', 'subject': 'Title'})!;
    expect(p.text, 'hi https://x.example');
    expect(p.subject, 'Title');
    expect(SharedPayload.fromChannel({'text': '   '}), isNull);
    expect(SharedPayload.fromChannel('nope'), isNull);
    expect(SharedPayload.fromChannel({'text': 'x', 'subject': ''})!.subject, isNull);
  });

  test('takeInitialShare returns the cold-start share', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getInitialShare') return {'text': 'https://youtu.be/a'};
      return null;
    });
    final intake = ShareIntake(enabled: true);
    addTearDown(intake.dispose);
    expect((await intake.takeInitialShare())!.text, 'https://youtu.be/a');
  });

  test('onShare from native is emitted on the stream', () async {
    final intake = ShareIntake(enabled: true);
    addTearDown(intake.dispose);
    final next = intake.shares.first;
    await messenger.handlePlatformMessage(
      ShareIntake.channelName,
      const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onShare', {'text': 'https://x.example/b'})),
      (_) {},
    );
    expect((await next).text, 'https://x.example/b');
  });

  test('disabled (non-Android) never touches the channel', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    final intake = ShareIntake(enabled: false);
    addTearDown(intake.dispose);
    expect(await intake.takeInitialShare(), isNull);
    expect(called, isFalse);
  });

  test('a missing native side is treated as no share', () async {
    final intake = ShareIntake(enabled: true); // no mock handler registered
    addTearDown(intake.dispose);
    expect(await intake.takeInitialShare(), isNull);
  });
}
