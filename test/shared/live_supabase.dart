// Helpers for tests that run against the LOCAL Supabase (`supabase start`).
// The keys are the public local-dev demo keys, not secrets.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

final liveAdmin = SupabaseClient(
  _url,
  _serviceRoleKey,
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

SupabaseClient _anon() => SupabaseClient(
  _url,
  _anonKey,
  authOptions: const AuthClientOptions(
    autoRefreshToken: false,
    authFlowType: AuthFlowType.implicit,
  ),
);

typedef LiveCouple = ({
  SupabaseClient husband,
  SupabaseClient wife,
  String husbandId,
  String wifeId,
  String coupleId,
});

/// Signs up a husband and wife, pairs them, and deletes both on tear-down.
Future<LiveCouple> livePairedCouple(String tag) async {
  final husband = _anon(), wife = _anon();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final husbandId = (await husband.auth.signUp(
    email: '$tag-h-$stamp@example.com',
    password: 'password123',
  )).user!.id;
  final wifeId = (await wife.auth.signUp(
    email: '$tag-w-$stamp@example.com',
    password: 'password123',
  )).user!.id;
  addTearDown(() async {
    await liveAdmin.auth.admin.deleteUser(husbandId);
    await liveAdmin.auth.admin.deleteUser(wifeId);
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
  return (
    husband: husband,
    wife: wife,
    husbandId: husbandId,
    wifeId: wifeId,
    coupleId: coupleId,
  );
}
