// Integration test against the LOCAL Supabase instance (see `supabase
// status`) for the Moments database rules: the reaction upsert, comments,
// and the hourly nudge target query. Same real-Supabase pattern as
// test/features/scoring/scoreboard_rpc_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:lovinity/features/moments/data/moments_repository.dart';
import 'package:lovinity/features/moments/domain/moment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

SupabaseClient _anonClient() => SupabaseClient(
  _supabaseUrl,
  _anonKey,
  authOptions: const AuthClientOptions(
    autoRefreshToken: false,
    authFlowType: AuthFlowType.implicit,
  ),
);

void main() {
  final admin = SupabaseClient(
    _supabaseUrl,
    _serviceRoleKey,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );

  test('moment reactions, comments and nudge targets', () async {
    final husband = _anonClient();
    final wife = _anonClient();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final husbandId = (await husband.auth.signUp(
      email: 'moments-h-$stamp@example.com',
      password: 'password123',
    )).user!.id;
    final wifeId = (await wife.auth.signUp(
      email: 'moments-w-$stamp@example.com',
      password: 'password123',
    )).user!.id;
    addTearDown(() async {
      await admin.auth.admin.deleteUser(husbandId);
      await admin.auth.admin.deleteUser(wifeId);
    });

    await husband
        .from('users')
        .update({'gender': 'male', 'timezone': 'UTC'})
        .eq('id', husbandId);
    await wife
        .from('users')
        .update({'gender': 'female', 'timezone': 'UTC'})
        .eq('id', wifeId);
    final invite = await husband.rpc('create_pairing_invite');
    final code =
        ((invite is List ? invite.first : invite) as Map)['code'] as String;
    final couple = await wife.rpc(
      'accept_pairing_invite',
      params: {'p_code': code},
    );
    final coupleId =
        ((couple is List ? couple.first : couple) as Map)['id'] as String;

    // The row alone is enough here; no file is needed for these rules.
    final row = await husband
        .from('moments')
        .insert({
          'couple_id': coupleId,
          'sender_id': husbandId,
          'media_path': '$coupleId/m/media.jpg',
          'media_mime': 'image/jpeg',
        })
        .select()
        .single();
    final moment = Moment.fromRow(row);

    // Reactions: the upsert must work, and a double tap must not fail.
    final repo = MomentsRepository(wife);
    await repo.toggleReaction(moment: moment, userId: wifeId, emoji: '❤️');
    await repo.toggleReaction(moment: moment, userId: wifeId, emoji: '❤️');
    await repo.comment(moment: moment, userId: wifeId, body: 'lovely');
    await repo.comment(moment: moment, userId: wifeId, body: 'again');
    final replies = await wife
        .from('moment_replies')
        .select('emoji, body')
        .eq('moment_id', moment.id);
    expect(replies.where((r) => r['emoji'] == '❤️'), hasLength(1));
    expect(replies.where((r) => r['body'] != null), hasLength(2));

    // Nudges: a junk preference must not break the run, and false opts out.
    final noon = DateTime.now().toUtc().copyWith(hour: 12, minute: 0);
    Future<List<String>> targets() async => [
      for (final t
          in await admin.rpc(
                'moment_nudge_targets',
                params: {'p_now': noon.toIso8601String()},
              )
              as List)
        t as String,
    ];
    await wife.from('user_preferences').upsert({
      'user_id': wifeId,
      'prefs': {'moment_nudges': 'x'},
    });
    expect(await targets(), contains(wifeId));
    await wife.from('user_preferences').upsert({
      'user_id': wifeId,
      'prefs': {'moment_nudges': false},
    });
    expect(await targets(), isNot(contains(wifeId)));
  });
}
