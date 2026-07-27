// Integration test against the LOCAL Supabase instance (see `supabase status`).
//
// The brief's original test mocked SupabaseClient/SupabaseQueryBuilder/
// PostgrestFilterBuilder with mocktail. As already established on this
// project (see test/features/onboarding/onboarding_repository_test.dart),
// that approach does not work against the installed supabase_flutter /
// postgrest: every builder in the chain (`SupabaseQueryBuilder`,
// `PostgrestFilterBuilder`) implements `Future<T>` directly rather than
// returning a plain Future from its methods, so mocktail's `thenReturn`
// refuses the stub and `thenAnswer` runs into the mock's inherited `then()`
// throwing at runtime. Per the task's sanctioned fallback, this test instead
// exercises `PreferencesRepository` against the local Supabase instance:
// sign up a throwaway user, call `setKey` twice (to prove merge behavior —
// a prior key survives, the new key is written), then `fetch` to verify the
// real jsonb round-trip. `user_preferences` is own-row RLS (Task 17), so the
// repository operates as the signed-up user (anon-key client), not the
// admin/service-role client (which is only used to clean up afterwards).
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/settings/data/preferences_repository.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

void main() {
  test(
    'setKey upserts prefs jsonb merged with the new key, verified via fetch',
    () async {
      final client = SupabaseClient(
        _supabaseUrl,
        _anonKey,
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final adminClient = SupabaseClient(
        _supabaseUrl,
        _serviceRoleKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );

      final email =
          'prefs-test-${DateTime.now().microsecondsSinceEpoch}@example.com';
      final signUpRes = await client.auth.signUp(
        email: email,
        password: 'password123',
      );
      final userId = signUpRes.user!.id;

      addTearDown(() async {
        await adminClient.auth.admin.deleteUser(userId);
      });

      final repo = PreferencesRepository(client);

      // Fetch before any prefs exist: should be empty.
      final before = await repo.fetch(userId);
      expect(before, isEmpty);

      // Seed a first key, then set a second: the first must survive the merge.
      await repo.setKey(userId: userId, key: 'foo', value: 1, current: before);
      final afterFirst = await repo.fetch(userId);
      expect(afterFirst['foo'], 1);

      await repo.setKey(
        userId: userId,
        key: 'share_cycle_default',
        value: true,
        current: afterFirst,
      );

      final after = await repo.fetch(userId);
      expect(after['share_cycle_default'], true);
      expect(after['foo'], 1);
    },
  );
}
