// Integration test against the LOCAL Supabase instance (see `supabase status`).
//
// The brief's original test mocked SupabaseClient/SupabaseQueryBuilder/
// PostgrestFilterBuilder with mocktail. That approach does not compile/run
// against the installed supabase_flutter (2.16.0) / postgrest (2.8.0):
// every builder in the chain (`SupabaseQueryBuilder`, `PostgrestFilterBuilder`)
// `implements Future<T>` directly rather than returning a plain Future from
// its methods. That makes mocktail's `thenReturn` refuse the stub (it
// special-cases Future-typed returns) and forces `thenAnswer`, but the
// callback's static return type must be `PostgrestFilterBuilder<dynamic>`
// (not a real Future) to satisfy the compiler — and when `await` on the mock
// then invokes the mock's inherited `then()` (since Mock doesn't stub it),
// it throws `type 'Null' is not a subtype of type 'Future<dynamic>'`. This
// was verified by hand (RED -> repo implemented -> still fails to compile ->
// fixed thenReturn->thenAnswer on all three builders -> runtime "Null is not
// a subtype of Future" from the mock's `then()`). Per the task's sanctioned
// fallback, this test instead exercises `OnboardingRepository.saveProfile`
// against the local Supabase instance and asserts the row written to
// `public.users`.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lovinity/features/onboarding/data/onboarding_repository.dart';

const _supabaseUrl = 'http://127.0.0.1:54321';
const _anonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

void main() {
  test(
    'saveProfile updates the users row with gender + profile fields',
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

      final email = 'onboarding-test-${DateTime.now().microsecondsSinceEpoch}@example.com';
      final signUpRes = await client.auth.signUp(
        email: email,
        password: 'password123',
      );
      final userId = signUpRes.user!.id;

      addTearDown(() async {
        await adminClient.auth.admin.deleteUser(userId);
      });

      final repo = OnboardingRepository(client);
      await repo.saveProfile(
        userId: userId,
        displayName: 'Aisha',
        gender: 'female',
        madhhab: 'hanafi',
        timezone: 'Asia/Dhaka',
        latitude: 23.8,
        longitude: 90.4,
      );

      final row = await client
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      expect(row['gender'], 'female');
      expect(row['display_name'], 'Aisha');
      expect(row['madhhab'], 'hanafi');
      expect(row['timezone'], 'Asia/Dhaka');
      expect(row['latitude'], 23.8);
      expect(row['longitude'], 90.4);
    },
  );
}
