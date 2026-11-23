import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/auth_controller.dart';

/// Mirrors supabase/config.toml: `minimum_password_length = 8`,
/// `password_requirements = "letters_digits"`.
const int kMinPasswordLength = 8;

/// The password rule's error message, or null when [password] passes.
String? passwordProblem(String password) {
  if (password.length < kMinPasswordLength) {
    return 'Password must be at least $kMinPasswordLength characters.';
  }
  if (!password.contains(RegExp(r'[A-Za-z]')) ||
      !password.contains(RegExp(r'[0-9]'))) {
    return 'Password must include both letters and numbers.';
  }
  return null;
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String? _gender;
  String _madhhab = 'shafi';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Returns the first validation problem, or null when the form is valid.
  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Please enter your name.';
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      return 'Please enter a valid email.';
    }
    if (_gender == null) return 'Please select whether you are a man or woman.';
    final passwordError = passwordProblem(_password.text);
    if (passwordError != null) return passwordError;
    if (_password.text != _confirm.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    try {
      await ref
          .read(authRepositoryProvider)
          .signUpWithProfile(
            email: email,
            password: _password.text,
            displayName: _name.text.trim(),
            gender: _gender!,
            madhhab: _madhhab,
          );
      if (!mounted) return;
      // Confirm-email is on, so there's no session yet — go verify the code.
      context.push(
        '/auth/otp?email=${Uri.encodeComponent(email)}&purpose=signup',
      );
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LovScaffold(
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: () => context.pop(),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 22),
                Text('Create your space', style: lovDisplay(context, size: 34)),
                const SizedBox(height: 8),
                Text(
                  'A private space for the two of you. Your spouse joins '
                  'with a code once you are in.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: context.lov.muted,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                ),
                const SizedBox(height: LovSpace.md),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline, size: 20),
                  ),
                ),
                const SizedBox(height: LovSpace.lg),
                Text('I am a', style: theme.textTheme.bodyMedium),
                const SizedBox(height: LovSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: _GenderChip(
                        label: 'Man',
                        selected: _gender == 'male',
                        onTap: () => setState(() => _gender = 'male'),
                      ),
                    ),
                    const SizedBox(width: LovSpace.md),
                    Expanded(
                      child: _GenderChip(
                        label: 'Woman',
                        selected: _gender == 'female',
                        onTap: () => setState(() => _gender = 'female'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LovSpace.lg),
                DropdownButtonFormField<String>(
                  initialValue: _madhhab,
                  decoration: const InputDecoration(
                    labelText: 'Madhhab',
                    helperText: 'Changes when Asr begins.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'shafi',
                      child: Text('Shāfiʿī / other'),
                    ),
                    DropdownMenuItem(value: 'hanafi', child: Text('Ḥanafī')),
                  ],
                  onChanged: (v) => setState(() => _madhhab = v ?? 'shafi'),
                ),
                const SizedBox(height: LovSpace.md),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                ),
                ListenableBuilder(
                  listenable: _password,
                  builder: (context, _) =>
                      _StrengthMeter(password: _password.text),
                ),
                const SizedBox(height: LovSpace.md),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: LovSpace.md),
                  LovInlineError(message: _error!),
                ],
                const SizedBox(height: LovSpace.xl),
                LovButton(
                  label: 'Create account',
                  onPressed: _busy ? null : _submit,
                  loading: _busy,
                  expand: true,
                ),
                const SizedBox(height: LovSpace.md),
                LovButton(
                  label: 'I already have an account',
                  variant: LovButtonVariant.text,
                  size: LovButtonSize.small,
                  onPressed: () => context.go('/auth/sign-in'),
                ),
                const SizedBox(height: LovSpace.lg),
                Text(
                  "We'll email you a code to confirm your address.",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.4)
              : null,
        ),
        child: Text(label),
      ),
    );
  }
}

/// Four bars and a word, from the same rules the server enforces.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    if (password.isEmpty) return const SizedBox(height: 8);
    var score = 0;
    if (password.length >= kMinPasswordLength) score++;
    if (password.contains(RegExp(r'[A-Za-z]')) &&
        password.contains(RegExp(r'[0-9]'))) {
      score++;
    }
    if (password.length >= 12) score++;
    if (password.contains(RegExp(r'[^A-Za-z0-9]'))) score++;
    final (label, color) = switch (score) {
      <= 1 => ('Weak', const Color(0xFFE5534B)),
      2 => ('Okay', p.accentLo),
      3 => ('Good', p.accent),
      _ => ('Strong', const Color(0xFF7BD88F)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < score ? color : p.line,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Password strength',
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
