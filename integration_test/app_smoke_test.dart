// On-device smoke test of the real app (iOS simulator, macOS) against the
// LOCAL Supabase. Run with:
//   flutter test integration_test -d <device> \
//     --dart-define-from-file=config/supabase.local.json
//
// Sets up a paired couple with the local service-role key, then drives the
// UI: sign in -> home -> chat -> settings -> sign out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lovinity/core/config/env.dart';
import 'package:lovinity/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

// Local stack's public demo service-role key (same one the repo's
// integration tests use); never a real project's key.
const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
const _password = 'password123';

/// pumpAndSettle never settles here (breathing/countdown animations loop).
Future<void> pumpUntil(WidgetTester t, Finder f,
    {Duration timeout = const Duration(seconds: 45)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  final onScreen = [
    for (final e in find.byType(Text).evaluate()) (e.widget as Text).data,
  ].whereType<String>().take(20).join(' | ');
  throw TestFailure('Timed out waiting for $f. On screen: $onScreen');
}

/// Creates a confirmed, signed-in user with a gender set; returns
/// (email, their own client). Gender goes through their own session, as in
/// the app: public.users is granted to authenticated, not service_role.
Future<(String, SupabaseClient)> _user(
    SupabaseClient admin, String tag, String gender) async {
  final email = 'smoke-$tag-${DateTime.now().microsecondsSinceEpoch}@example.com';
  final res = await admin.auth.admin.createUser(
      AdminUserAttributes(email: email, password: _password, emailConfirm: true));
  final id = res.user!.id;
  addTearDown(() => admin.auth.admin.deleteUser(id));
  final client = SupabaseClient(Env.supabaseUrl, Env.supabaseAnonKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  await client.auth.signInWithPassword(email: email, password: _password);
  await client.from('users').update({'gender': gender}).eq('id', id);
  return (email, client);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sign in, open chat and settings, sign out', (tester) async {
    final admin = SupabaseClient(Env.supabaseUrl, _serviceRoleKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final (husbandEmail, husband) = await _user(admin, 'h', 'male');
    final (_, wife) = await _user(admin, 'w', 'female');

    // Pair them through the real RPCs, outside the UI.
    final invite = await husband.rpc('create_pairing_invite');
    final code = ((invite is List ? invite.first : invite) as Map)['code'] as String;
    await wife.rpc('accept_pairing_invite', params: {'p_code': code});

    await app.main();
    // A session left by an earlier run is restored asynchronously, possibly
    // after a one-off signOut; keep clearing it until sign-in shows.
    final emailField = find.widgetWithText(TextField, 'Email');
    final end = DateTime.now().add(const Duration(seconds: 45));
    while (emailField.evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (Supabase.instance.client.auth.currentSession != null) {
        await Supabase.instance.client.auth.signOut();
      }
    }
    await pumpUntil(tester, emailField);
    await tester.enterText(emailField, husbandEmail);
    await tester.enterText(find.widgetWithText(TextField, 'Password'), _password);
    await tester.tap(find.text('Sign in').last);

    // Paired + onboarded => home.
    await pumpUntil(tester, find.byTooltip('Settings'));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Chat'));
    await pumpUntil(tester, find.byType(TextField));
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    // Home stays mounted under chat, so wait for chat's pop transition to
    // finish, or the next tap lands on the departing chat page.
    for (var i = 0; i < 40 && find.byType(TextField).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpUntil(tester, find.byTooltip('Settings'));

    await tester.tap(find.byTooltip('Settings'));
    await pumpUntil(tester, find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await pumpUntil(tester, emailField);
    expect(tester.takeException(), isNull);
  });
}
