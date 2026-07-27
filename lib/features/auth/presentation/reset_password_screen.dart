import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/crypto/crypto_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/auth_controller.dart';
import 'sign_up_screen.dart' show kMinPasswordLength;

/// Code + new password in one screen: verifying the recovery code signs the
/// user in, so splitting the steps would leave a session whose password is
/// still the forgotten one.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _slots = LovDigitSlotsController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  String _code = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_code.length != Env.otpLength) {
      return 'Enter the ${Env.otpLength}-digit code from your email.';
    }
    if (_password.text.length < kMinPasswordLength) {
      return 'Password must be at least $kMinPasswordLength characters.';
    }
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
    try {
      final repo = ref.read(authRepositoryProvider);
      // Verifying the code returns a session; set the new password on it.
      await repo.verifyRecoveryOtp(email: widget.email, token: _code);
      await repo.updatePassword(_password.text);
      await ref.read(ensureRegisteredProvider)();
      unawaited(LovHaptics.medium());
      if (mounted) context.go('/home');
    } on AppFailure catch (e) {
      _slots.shake();
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
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose a new password',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: LovSpace.sm),
                Text(
                  'Sent to ${widget.email}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: LovSpace.xxl),
                LovDigitSlots(
                  length: Env.otpLength,
                  mode: LovDigitMode.numeric,
                  controller: _slots,
                  // No auto-submit: the password fields still need filling.
                  onCompleted: (v) => _code = v,
                  onChanged: (v) {
                    _code = v;
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: LovSpace.xl),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                ),
                const SizedBox(height: LovSpace.md),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
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
                  label: 'Set new password',
                  onPressed: _busy ? null : _submit,
                  loading: _busy,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
