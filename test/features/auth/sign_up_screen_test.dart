import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:lovinity/features/auth/data/auth_repository.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/auth/presentation/sign_up_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

class _FakeAuthResponse extends Mock implements AuthResponse {}

/// Minimal router so the happy path's context.push has somewhere to go.
Widget _app(_MockAuthRepo repo) {
  final router = GoRouter(
    initialLocation: '/auth/sign-up',
    routes: [
      GoRoute(
        path: '/auth/sign-up',
        builder: (_, _) => const SignUpScreen(),
      ),
      GoRoute(
        path: '/auth/otp',
        builder: (_, _) => const Scaffold(body: Text('OTP SCREEN')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _fill(
  WidgetTester tester, {
  String name = 'Ridwan',
  String email = 'r@example.com',
  String password = 'password123',
  String confirm = 'password123',
  bool pickGender = true,
}) async {
  await tester.enterText(find.byType(TextField).at(0), name);
  await tester.enterText(find.byType(TextField).at(1), email);
  if (pickGender) {
    await tester.tap(find.text('Man'));
    await tester.pump();
  }
  await tester.enterText(find.byType(TextField).at(2), password);
  await tester.enterText(find.byType(TextField).at(3), confirm);
}

Future<void> _submit(WidgetTester tester) async {
  // The form is taller than the default 800x600 test viewport; scroll the
  // button into view so the tap actually lands on it.
  await tester.ensureVisible(find.text('Create account'));
  await tester.pump();
  await tester.tap(find.text('Create account'));
  await tester.pump();
}

void main() {
  late _MockAuthRepo repo;

  setUp(() => repo = _MockAuthRepo());

  testWidgets('rejects an empty name', (tester) async {
    await tester.pumpWidget(_app(repo));
    await _fill(tester, name: '');
    await _submit(tester);
    expect(find.textContaining('enter your name'), findsOneWidget);
    verifyNever(() => repo.signUpWithProfile(
        email: any(named: 'email'),
        password: any(named: 'password'),
        displayName: any(named: 'displayName'),
        gender: any(named: 'gender'),
        madhhab: any(named: 'madhhab')));
  });

  testWidgets('rejects an invalid email', (tester) async {
    await tester.pumpWidget(_app(repo));
    await _fill(tester, email: 'not-an-email');
    await _submit(tester);
    expect(find.textContaining('valid email'), findsOneWidget);
  });

  testWidgets('requires a gender selection', (tester) async {
    await tester.pumpWidget(_app(repo));
    await _fill(tester, pickGender: false);
    await _submit(tester);
    expect(find.textContaining('man or woman'), findsOneWidget);
  });

  testWidgets('rejects a password shorter than the minimum', (tester) async {
    await tester.pumpWidget(_app(repo));
    await _fill(tester, password: 'short', confirm: 'short');
    await _submit(tester);
    expect(find.textContaining('at least $kMinPasswordLength'), findsOneWidget);
  });

  testWidgets('rejects mismatched passwords', (tester) async {
    await tester.pumpWidget(_app(repo));
    await _fill(tester, password: 'password123', confirm: 'password124');
    await _submit(tester);
    expect(find.textContaining('do not match'), findsOneWidget);
  });

  testWidgets('valid form signs up with the captured profile and goes to OTP',
      (tester) async {
    when(() => repo.signUpWithProfile(
          email: any(named: 'email'),
          password: any(named: 'password'),
          displayName: any(named: 'displayName'),
          gender: any(named: 'gender'),
          madhhab: any(named: 'madhhab'),
        )).thenAnswer((_) async => _FakeAuthResponse());

    await tester.pumpWidget(_app(repo));
    await _fill(tester);
    await _submit(tester);
    await tester.pumpAndSettle();

    final captured = verify(() => repo.signUpWithProfile(
          email: captureAny(named: 'email'),
          password: captureAny(named: 'password'),
          displayName: captureAny(named: 'displayName'),
          gender: captureAny(named: 'gender'),
          madhhab: captureAny(named: 'madhhab'),
        )).captured;
    expect(captured[0], 'r@example.com');
    expect(captured[2], 'Ridwan');
    expect(captured[3], 'male');
    expect(captured[4], 'shafi'); // default

    expect(find.text('OTP SCREEN'), findsOneWidget);
  });
}
