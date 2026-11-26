import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/core/theme/theme.dart';
import 'package:lovinity/features/chat/domain/chat_providers.dart';
import 'package:lovinity/features/chat/presentation/media_picker.dart';
import 'package:lovinity/features/home/domain/home_providers.dart';
import 'package:lovinity/features/pairing/domain/pairing_providers.dart';
import 'package:lovinity/features/wall/data/link_preview_service.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';
import 'package:lovinity/features/wall/domain/wall_providers.dart';
import 'package:lovinity/features/wall/presentation/add_to_wall_sheet.dart';
import 'package:lovinity/shared/models/couple.dart';

import 'fakes.dart';

const _couple = Couple(
  id: 'c1',
  memberA: 'me',
  memberB: 'sp',
  status: 'active',
  longDistance: false,
);

class _FakePicker implements MediaPicker {
  PickedPhoto? photo;
  PickedVideo? video;
  Object? videoError;
  int? videoThumbWidth;

  @override
  Future<PickedPhoto?> pickPhoto(MediaSource source) async => photo;

  @override
  Future<PickedVideo?> pickVideo(
    MediaSource source, {
    int thumbnailMaxWidth = 200,
  }) async {
    videoThumbWidth = thumbnailMaxWidth;
    if (videoError != null) throw videoError!;
    return video;
  }
}

final _photo = PickedPhoto(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'image/jpeg',
  width: 1,
  height: 1,
  thumbnailBytes: Uint8List.fromList([9]),
);

Future<void> _open(
  WidgetTester tester, {
  required FakeWallRepository repo,
  FakeLinkPreviewService? previews,
  String? initialUrl,
  bool clipboardHasText = false,
  String clipboardText = '',
  MediaPicker? picker,
}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.hasStrings') {
        return {'value': clipboardHasText};
      }
      if (call.method == 'Clipboard.getData') return {'text': clipboardText};
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        wallRepositoryProvider.overrideWithValue(repo),
        linkPreviewServiceProvider.overrideWithValue(
          previews ?? FakeLinkPreviewService(),
        ),
        wallSelfIdProvider.overrideWithValue('me'),
        if (picker != null) mediaPickerProvider.overrideWithValue(picker),
        currentCoupleProvider.overrideWith((ref) => Stream.value(_couple)),
        spouseProfileProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: LovTheme.dark(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    showAddToWallSheet(ctx, initialUrl: initialUrl),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(); // couple stream
  await tester.tap(find.text('open'));
  // Not pumpAndSettle: a loading preview shows a shimmer that animates
  // forever, which would make pumpAndSettle time out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Finder get _shareButton =>
    find.widgetWithText(FilledButton, 'Share with your partner');

void main() {
  testWidgets('button is disabled until there is a link or a note', (
    tester,
  ) async {
    await _open(tester, repo: FakeWallRepository());
    expect(tester.widget<FilledButton>(_shareButton).onPressed, isNull);
  });

  testWidgets('posts a note-only item', (tester) async {
    final repo = FakeWallRepository();
    await _open(tester, repo: repo);
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a note… (optional)'),
      'call your mum Friday',
    );
    await tester.pump();
    await tester.tap(_shareButton);
    await tester.pumpAndSettle();
    expect(repo.added.single.args['source'], WallSource.note);
    expect(repo.added.single.args['url'], isNull);
    expect(repo.added.single.args['note'], 'call your mum Friday');
    expect(find.byType(AddToWallSheet), findsNothing, reason: 'sheet closes');
  });

  testWidgets(
    'a link loads a preview and posts it with the chosen collection',
    (tester) async {
      final repo = FakeWallRepository();
      final previews = FakeLinkPreviewService(
        (_) async => const LinkPreview(
          title: 'The 10-minute habit',
          imageUrl: 'https://i/t.jpg',
        ),
      );
      await _open(tester, repo: repo, previews: previews);
      await tester.enterText(
        find.widgetWithText(TextField, 'Paste a link'),
        'https://youtu.be/abc',
      );
      await tester.pump(const Duration(milliseconds: 450)); // debounce
      await tester.pump();
      expect(previews.requested, ['https://youtu.be/abc']);
      expect(find.text('The 10-minute habit'), findsOneWidget);

      await tester.tap(find.text('Deen'));
      await tester.pump();
      await tester.tap(_shareButton);
      await tester.pumpAndSettle();
      final args = repo.added.single.args;
      expect(args['url'], 'https://youtu.be/abc');
      expect(args['title'], 'The 10-minute habit');
      expect(args['imageUrl'], 'https://i/t.jpg');
      expect(args['source'], WallSource.youtube);
      expect(args['collection'], WallCollection.deen);
    },
  );

  testWidgets('waits for a slow preview when submitting', (tester) async {
    final repo = FakeWallRepository();
    final completer = Completer<LinkPreview?>();
    await _open(
      tester,
      repo: repo,
      previews: FakeLinkPreviewService((_) => completer.future),
      initialUrl: 'https://example.com/r',
    );
    await tester.pump();
    await tester.tap(_shareButton);
    await tester.pump();
    expect(repo.added, isEmpty);
    completer.complete(const LinkPreview(title: 'Biryani'));
    await tester.pumpAndSettle();
    expect(repo.added.single.args['title'], 'Biryani');
  });

  testWidgets('falls back to the domain as title when there is no preview', (
    tester,
  ) async {
    final repo = FakeWallRepository();
    await _open(tester, repo: repo, initialUrl: 'https://www.example.com/x');
    await tester.pump();
    await tester.tap(_shareButton);
    await tester.pumpAndSettle();
    expect(repo.added.single.args['title'], 'example.com');
    expect(repo.added.single.args['source'], WallSource.article);
  });

  testWidgets('text that is not a link shows an error and disables sharing', (
    tester,
  ) async {
    await _open(tester, repo: FakeWallRepository());
    await tester.enterText(
      find.widgetWithText(TextField, 'Paste a link'),
      'hello there',
    );
    await tester.pump();
    expect(find.text("That doesn't look like a link"), findsOneWidget);
    expect(tester.widget<FilledButton>(_shareButton).onPressed, isNull);
    await tester.pump(
      const Duration(milliseconds: 450),
    ); // let the debounce timer fire
  });

  testWidgets(
    'paste pill appears only when the clipboard has text, and fills the link',
    (tester) async {
      await _open(
        tester,
        repo: FakeWallRepository(),
        clipboardHasText: true,
        clipboardText: 'look https://youtu.be/xyz',
      );
      await tester.pump();
      expect(find.text('Paste copied link'), findsOneWidget);
      await tester.tap(find.text('Paste copied link'));
      await tester.pump();
      expect(find.text('https://youtu.be/xyz'), findsOneWidget);
      expect(find.text('Paste copied link'), findsNothing);
      // Let the debounce timer + preview fetch finish (no pending timers).
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();
    },
  );

  testWidgets('a failed post keeps the sheet open with a retry', (
    tester,
  ) async {
    final repo = FakeWallRepository()..throwOnAdd = Exception('offline');
    await _open(tester, repo: repo);
    await tester.enterText(
      find.widgetWithText(TextField, 'Add a note… (optional)'),
      'keep me',
    );
    await tester.pump();
    await tester.tap(_shareButton);
    await tester.pumpAndSettle();
    expect(find.byType(AddToWallSheet), findsOneWidget);
    expect(find.textContaining("Couldn't share"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.text('keep me'), findsOneWidget);
  });

  Future<void> pickFrom(WidgetTester tester, String choice) async {
    await tester.tap(find.text('Photo / Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice));
    await tester.pumpAndSettle();
  }

  testWidgets('a picked photo hides the link field and posts as image/jpeg', (
    tester,
  ) async {
    final repo = FakeWallRepository();
    await _open(tester, repo: repo, picker: _FakePicker()..photo = _photo);
    await pickFrom(tester, 'Photo Library');
    expect(find.widgetWithText(TextField, 'Paste a link'), findsNothing);
    expect(find.byTooltip('Remove photo or video'), findsOneWidget);
    await tester.tap(_shareButton);
    await tester.pumpAndSettle();
    final args = repo.added.single.args;
    expect(args['mimeType'], 'image/jpeg');
    expect(args['thumbnailBytes'], isNull);
    expect(find.byType(AddToWallSheet), findsNothing);
  });

  testWidgets('removing the media brings the link field back', (tester) async {
    await _open(
      tester,
      repo: FakeWallRepository(),
      picker: _FakePicker()..photo = _photo,
    );
    await pickFrom(tester, 'Photo Library');
    await tester.tap(find.byTooltip('Remove photo or video'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Paste a link'), findsOneWidget);
  });

  testWidgets('a video posts with its 800px thumbnail', (tester) async {
    final repo = FakeWallRepository();
    final picker = _FakePicker()
      ..video = PickedVideo(
        bytes: Uint8List.fromList([4]),
        mimeType: 'video/quicktime',
        durationMs: 1000,
        thumbnailBytes: Uint8List.fromList([7, 7]),
      );
    await _open(tester, repo: repo, picker: picker);
    await pickFrom(tester, 'Video Library');
    expect(picker.videoThumbWidth, 800);
    await tester.tap(_shareButton);
    await tester.pumpAndSettle();
    final args = repo.added.single.args;
    expect(args['mimeType'], 'video/quicktime');
    expect(args['thumbnailBytes'], Uint8List.fromList([7, 7]));
  });

  testWidgets('a video with no thumbnail is rejected, not posted', (
    tester,
  ) async {
    final repo = FakeWallRepository();
    final picker = _FakePicker()
      ..video = PickedVideo(
        bytes: Uint8List.fromList([4]),
        mimeType: 'video/mp4',
        durationMs: 1000,
        thumbnailBytes: Uint8List(0),
      );
    await _open(tester, repo: repo, picker: picker);
    await pickFrom(tester, 'Video Library');
    expect(find.textContaining("Couldn't read that video"), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(repo.added, isEmpty);
  });

  testWidgets('a 61 s video is rejected with an inline error and not posted', (
    tester,
  ) async {
    final repo = FakeWallRepository();
    final picker = _FakePicker()
      ..videoError = MediaRejected(
        videoRejection(bytes: 4, durationMs: 61000)!,
      );
    await _open(tester, repo: repo, picker: picker);
    await pickFrom(tester, 'Video Library');
    expect(find.text('Videos can be up to 60 seconds'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
    expect(find.byTooltip('Remove photo or video'), findsNothing);
    expect(repo.added, isEmpty);
  });

  testWidgets('a video over 50 MiB is rejected inline and not attached', (
    tester,
  ) async {
    final repo = FakeWallRepository();
    final picker = _FakePicker()
      ..videoError = MediaRejected(
        videoRejection(bytes: maxVideoBytes + 1, durationMs: 30000)!,
      );
    await _open(tester, repo: repo, picker: picker);
    await pickFrom(tester, 'Video Library');
    expect(find.textContaining('too large (max 50 MB)'), findsOneWidget);
    expect(find.byTooltip('Remove photo or video'), findsNothing);
    expect(repo.added, isEmpty);
  });

  testWidgets('a failed media upload keeps the sheet open with a retry', (
    tester,
  ) async {
    final repo = FakeWallRepository()..throwOnAdd = Exception('offline');
    await _open(tester, repo: repo, picker: _FakePicker()..photo = _photo);
    await pickFrom(tester, 'Photo Library');
    await tester.tap(_shareButton);
    await tester.pumpAndSettle();
    expect(find.byType(AddToWallSheet), findsOneWidget);
    expect(find.textContaining("Couldn't share"), findsOneWidget);
    repo.throwOnAdd = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();
    expect(repo.added, hasLength(1));
    expect(find.byType(AddToWallSheet), findsNothing);
  });
}
