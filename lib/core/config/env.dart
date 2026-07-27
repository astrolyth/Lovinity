/// Compile-time env vars, passed via `--dart-define`.
///
/// Cloud (production) — fill in `config/supabase.cloud.json` (gitignored) with
/// your project's URL + anon/publishable key from the Supabase dashboard
/// (Settings → API), then:
///   flutter run --dart-define-from-file=config/supabase.cloud.json
///
/// Local Supabase (Docker) — run `supabase status` for the URL + anon key:
///   flutter run --dart-define=SUPABASE_URL=http://localhost:54321 \
///               --dart-define=SUPABASE_ANON_KEY=`local-anon-key`
class Env {
  const Env._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://localhost:54321',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Email OTP length. Must match the Supabase project's "Email OTP Length"
  /// (GoTrue default is 6). Override via
  /// `--dart-define=OTP_LENGTH=8` (or the dart-define file) if your project
  /// issues a different length.
  static const otpLength = int.fromEnvironment('OTP_LENGTH', defaultValue: 6);

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;
}
