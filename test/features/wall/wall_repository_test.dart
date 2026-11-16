// Integration test against the LOCAL Supabase instance (`supabase start`,
// migrations applied with `supabase db reset`). Same approach as
// test/features/scoring/scoreboard_repository_test.dart: real users are
// signed up and paired through the app's own RPCs so RLS is exercised for
// real (mocktail can't stub the postgrest builder chain).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/wall/data/wall_repository.dart';
import 'package:lovinity/features/wall/domain/wall_models.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

SupabaseClient _anonClient() => SupabaseClient(
      _supabaseUrl,
      _anonKey,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );

void main() {
  late SupabaseClient clientA, clientB, clientC;
  late WallRepository repoA, repoB, repoC;
  late String coupleId, userA, userB;

  setUpAll(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    clientA = _anonClient();
    clientB = _anonClient();
    clientC = _anonClient();
    userA = (await clientA.auth.signUp(
            email: 'wall-a-$stamp@example.com', password: 'password123'))
        .user!
        .id;
    userB = (await clientB.auth.signUp(
            email: 'wall-b-$stamp@example.com', password: 'password123'))
        .user!
        .id;
    await clientC.auth.signUp(email: 'wall-c-$stamp@example.com', password: 'password123');
    // accept_pairing_invite requires different, non-null genders.
    await clientA.from('users').update({'gender': 'male'}).eq('id', userA);
    await clientB.from('users').update({'gender': 'female'}).eq('id', userB);
    final invite = await clientA.rpc('create_pairing_invite');
    final code = Map<String, dynamic>.from(
        (invite is List ? invite.first : invite) as Map)['code'] as String;
    final couple = await clientB.rpc('accept_pairing_invite', params: {'p_code': code});
    coupleId = Map<String, dynamic>.from(
        (couple is List ? couple.first : couple) as Map)['id'] as String;
    repoA = WallRepository(clientA);
    repoB = WallRepository(clientB);
    repoC = WallRepository(clientC);
  });

  tearDownAll(() async {
    await clientA.dispose();
    await clientB.dispose();
    await clientC.dispose();
  });

  test('addItem round-trips and appears in watchItems, newest first', () async {
    final older = await repoA.addItem(
        coupleId: coupleId, userId: userA, source: WallSource.note, note: 'first note');
    final link = await repoA.addItem(
      coupleId: coupleId,
      userId: userA,
      url: 'https://youtu.be/abc',
      title: 'A video',
      imageUrl: 'https://i.ytimg.com/x.jpg',
      source: WallSource.youtube,
      collection: WallCollection.deen,
      note: 'after Fajr?',
    );
    expect(link.source, WallSource.youtube);
    expect(link.collection, WallCollection.deen);

    final items = await repoB.watchItems(coupleId).first;
    final ids = items.map((i) => i.id).toList();
    expect(ids.indexOf(link.id), lessThan(ids.indexOf(older.id)));
    expect(items.firstWhere((i) => i.id == link.id).title, 'A video');
  });

  test('spouse can pin and file, but not delete, the other\'s item', () async {
    final item = await repoA.addItem(
        coupleId: coupleId, userId: userA, source: WallSource.note, note: 'pin me');
    await repoB.setPinned(item.id, true);
    await repoB.setCollection(item.id, WallCollection.home);
    await repoB.deleteItem(item); // RLS: silently affects 0 rows

    final after = (await repoA.watchItems(coupleId).first)
        .firstWhere((i) => i.id == item.id);
    expect(after.isPinned, isTrue);
    expect(after.collection, WallCollection.home);

    await repoA.deleteItem(item);
    final gone = await repoA.watchItems(coupleId).first;
    expect(gone.any((i) => i.id == item.id), isFalse);
  });

  test('cannot post as the spouse', () async {
    expect(
      () => repoA.addItem(
          coupleId: coupleId, userId: userB, source: WallSource.note, note: 'spoof'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('addReaction twice is idempotent; removeReaction removes it', () async {
    final item = await repoA.addItem(
        coupleId: coupleId, userId: userA, source: WallSource.note, note: 'react');
    await repoB.addReaction(
        coupleId: coupleId, itemId: item.id, userId: userB, kind: WallReactionKind.heart);
    await repoB.addReaction(
        coupleId: coupleId, itemId: item.id, userId: userB, kind: WallReactionKind.heart);
    var reactions = (await repoA.watchReactions(coupleId).first)
        .where((r) => r.itemId == item.id)
        .toList();
    expect(reactions, hasLength(1));
    expect(reactions.single.kind, WallReactionKind.heart);

    await repoB.removeReaction(itemId: item.id, userId: userB, kind: WallReactionKind.heart);
    reactions = (await repoA.watchReactions(coupleId).first)
        .where((r) => r.itemId == item.id)
        .toList();
    expect(reactions, isEmpty);
  });

  test('comments: add, list oldest first, spouse cannot delete mine', () async {
    final item = await repoA.addItem(
        coupleId: coupleId, userId: userA, source: WallSource.note, note: 'talk');
    await repoA.addComment(coupleId: coupleId, itemId: item.id, userId: userA, body: 'one');
    await repoB.addComment(coupleId: coupleId, itemId: item.id, userId: userB, body: 'two');
    var comments = (await repoA.watchComments(coupleId).first)
        .where((c) => c.itemId == item.id)
        .toList();
    expect(comments.map((c) => c.body), ['one', 'two']);

    await repoB.deleteComment(comments.first.id); // not B's -> no-op
    comments = (await repoA.watchComments(coupleId).first)
        .where((c) => c.itemId == item.id)
        .toList();
    expect(comments, hasLength(2));
  });

  test('outsider sees nothing', () async {
    await repoA.addItem(
        coupleId: coupleId, userId: userA, source: WallSource.note, note: 'private');
    expect(await repoC.watchItems(coupleId).first, isEmpty);
    expect(await repoC.watchComments(coupleId).first, isEmpty);
  });

  test('database rejects a non-http url', () async {
    expect(
      () => repoA.addItem(
          coupleId: coupleId, userId: userA, url: 'ftp://x.example', source: WallSource.article),
      throwsA(isA<PostgrestException>()),
    );
  });

  group('media', () {
    final bytes = Uint8List.fromList(List.generate(64, (i) => i));

    Future<List<FileObject>> listDir(String dir) =>
        clientA.storage.from('wall-media').list(path: dir);

    test('photo: uploads, signed URL downloads, spouse reads, outsider cannot',
        () async {
      final item = await repoA.addMediaItem(
          coupleId: coupleId,
          userId: userA,
          bytes: bytes,
          mimeType: 'image/jpeg',
          note: 'us');
      expect(item.hasMedia, isTrue);
      expect(item.source, WallSource.photo);
      expect(item.mediaMime, 'image/jpeg');
      expect(item.mediaPath, '$coupleId/${item.id}/media.jpg');
      expect(item.thumbPath, item.mediaPath);

      for (final repo in [repoA, repoB]) {
        final res = await http.get(Uri.parse(await repo.signedUrl(item.thumbPath!)));
        expect(res.statusCode, 200);
        expect(res.bodyBytes, isNotEmpty);
      }
      await expectLater(repoC.signedUrl(item.mediaPath!), throwsA(anything));
    });

    test('video: mov mime stores mp4 path and uploads the thumbnail', () async {
      final item = await repoA.addMediaItem(
          coupleId: coupleId,
          userId: userA,
          bytes: bytes,
          mimeType: 'video/quicktime',
          thumbnailBytes: bytes);
      expect(item.source, WallSource.video);
      expect(item.mediaMime, 'video/quicktime');
      expect(item.mediaPath, '$coupleId/${item.id}/media.mp4');
      expect(item.thumbPath, '$coupleId/${item.id}/thumb.jpg');
      final res = await http.get(Uri.parse(await repoB.signedUrl(item.thumbPath!)));
      expect(res.statusCode, 200);
      expect(res.bodyBytes, isNotEmpty);
    });

    test('failed insert leaves no object behind', () async {
      const badCouple = '00000000-0000-0000-0000-000000000000';
      // Storage RLS rejects the upload itself for a foreign couple, so the
      // insert-failure path is exercised with a valid folder but a spoofed author.
      await expectLater(
        repoA.addMediaItem(
            coupleId: coupleId, userId: userB, bytes: bytes, mimeType: 'image/jpeg'),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        repoA.addMediaItem(
            coupleId: badCouple, userId: userA, bytes: bytes, mimeType: 'image/jpeg'),
        throwsA(anything),
      );
      expect(await listDir(badCouple), isEmpty);
      final dirs = await listDir(coupleId);
      final items = (await repoA.watchItems(coupleId).first).map((i) => i.id).toSet();
      expect(dirs.where((d) => !items.contains(d.name)), isEmpty);
    });

    test('deleteItem removes the row and both objects via the Storage API',
        () async {
      final item = await repoA.addMediaItem(
          coupleId: coupleId,
          userId: userA,
          bytes: bytes,
          mimeType: 'video/mp4',
          thumbnailBytes: bytes);
      final dir = '$coupleId/${item.id}';
      expect(await listDir(dir), hasLength(2));
      await repoA.deleteItem(item);
      expect(await listDir(dir), isEmpty);
      final gone = await repoA.watchItems(coupleId).first;
      expect(gone.any((i) => i.id == item.id), isFalse);
    });
  });
}
