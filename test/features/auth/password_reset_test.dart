import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:lovinity/features/auth/data/auth_repository.dart';
import 'package:lovinity/features/auth/domain/auth_controller.dart';
import 'package:lovinity/features/auth/presentation/forgot_password_screen.dart';
import 'package:lovinity/features/auth/presentation/reset_password_screen.dart';

class _MockAuthRepo extends Mock implements AuthRepository {}

Widget _app(_MockAuthRepo repo, String initial) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/reset-password',
        builder: (_, state) => ResetPasswordScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
    ],
  );
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late _MockAuthRepo repo;
  setUp(() => repo = _MockAuthRepo());

  group('forgot password', () {
    testWidgets('rejects an invalid email and does not call the repository',
        (tester) async {
      await tester.pumpWidget(_app(repo, '/auth/forgot-password'));
      await tester.enterText(find.byType(TextField).first, 'nope');
      await tester.tap(find.text('Send reset code'));
      await tester.pump();
      expect(find.textContaining('valid email'), findsOneWidget);
      verifyNever(() => repo.sendPasswordReset(any()));
    });

    testWidgets('valid email sends a reset code and moves to reset screen',
        (tester) async {
      when(() => repo.sendPasswordReset(any())).thenAnswer((_) async {});
      await tester.pumpWidget(_app(repo, '/auth/forgot-password'));
      await tester.enterText(find.byType(TextField).first, 'r@example.com');
      await tester.tap(find.text('Send reset code'));
      await tester.pumpAndSettle();

      verify(() => repo.sendPasswordReset('r@example.com')).called(1);
      expect(find.text('Choose a new password'), findsOneWidget);
    });
  });

  group('reset password', () {
    testWidgets('requires the emailed code before doing anything',
        (tester) async {
      await tester.pumpWidget(
        _app(repo, '/auth/reset-password?email=r%40example.com'),
      );
      await tester.pumpAndSettle(); // let entry animations finish
      await tester.ensureVisible(find.text('Set new password'));
      await tester.pump();
      await tester.tap(find.text('Set new password'));
      await tester.pumpAndSettle();

      expect(find.textContaining('digit code'), findsOneWidget);
      verifyNever(() => repo.verifyRecoveryOtp(
          email: any(named: 'email'), token: any(named: 'token')));
      verifyNever(() => repo.updatePassword(any()));
    });

    testWidgets('shows the address the code was sent to', (tester) async {
      await tester.pumpWidget(
        _app(repo, '/auth/reset-password?email=r%40example.com'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('r@example.com'), findsOneWidget);
    });
  });
}
