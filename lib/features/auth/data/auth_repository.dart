import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failures.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> authStateChanges() => _client.auth.onAuthStateChange;

  Future<void> sendEmailOtp(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Sign up with the profile captured on the form.
  ///
  /// With "Confirm email" on, no session comes back here — the profile is sent
  /// as auth metadata and `handle_new_auth_user` persists it to public.users
  /// server-side, so it survives until the user confirms and signs in.
  Future<AuthResponse> signUpWithProfile({
    required String email,
    required String password,
    required String displayName,
    required String gender,
    required String madhhab,
  }) async {
    try {
      return await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'display_name': displayName,
          'gender': gender,
          'madhhab': madhhab,
        },
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Emails a recovery code (the "Reset Password" template must include
  /// `{{ .Token }}`, otherwise there is no code to enter).
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Confirms a sign-up with the emailed code; returns a session.
  Future<AuthResponse> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    try {
      return await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Verifies a recovery code; returns a session so the password can be set.
  Future<AuthResponse> verifyRecoveryOtp({
    required String email,
    required String token,
  }) async {
    try {
      return await _client.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: token,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Sets a new password for the currently-authenticated user.
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<AuthResponse> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      return await _client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: token,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<void> signOut() async {
    // Only clear the auth session. The Signal identity + local data are NOT
    // wiped here so the SAME user signing back in keeps their history and
    // device registration; a DIFFERENT user is detected and wiped by the
    // account-switch guard in ensureRegisteredProvider.
    await _client.auth.signOut();
  }
}
