import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/crypto/crypto_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/auth_controller.dart';

/// Why we're asking for a code — decides which verify call is made.
enum OtpPurpose {
  /// Passwordless sign-in (also creates the account for a new email).
  signIn,

  /// Confirming a just-created email/password account.
  signUp,
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    super.key,
    required this.email,
    this.purpose = OtpPurpose.signIn,
  });

  final String email;
  final OtpPurpose purpose;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  // Matches GoTrue's default per-email resend interval, so the button
  // re-enables roughly when the server will accept another request.
  static const _resendCooldownSeconds = 60;

  final _slots = LovDigitSlotsController();
  bool _busy = false;
  String? _error;
  bool _resending = false;
  int _secondsLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // A code was just sent when this screen opened; start the cooldown.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendEmailOtp(widget.email);
      _slots.clear();
      unawaited(LovHaptics.light());
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('New code sent.')));
      }
      _startCooldown();
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not resend the code. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify(String code) async {
    if (code.length != Env.otpLength) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(authRepositoryProvider);
      switch (widget.purpose) {
        case OtpPurpose.signIn:
          await repo.verifyEmailOtp(email: widget.email, token: code);
        case OtpPurpose.signUp:
          await repo.verifySignupOtp(email: widget.email, token: code);
      }
      await ref.read(ensureRegisteredProvider)();
      unawaited(LovHaptics.medium());
    } on AppFailure catch (e) {
      _slots.shake();
      unawaited(LovHaptics.medium());
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      _slots.shake();
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
                LovEnter(
                  child: Text(
                    'Enter your code',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                ),
                const SizedBox(height: LovSpace.sm),
                LovEnter(
                  delay: const Duration(milliseconds: 60),
                  child: Text(
                    'Sent to ${widget.email}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: LovSpace.xxxl),
                LovDigitSlots(
                  length: Env.otpLength,
                  mode: LovDigitMode.numeric,
                  controller: _slots,
                  onCompleted: _verify,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: LovSpace.lg),
                  LovInlineError(message: _error!),
                ],
                const SizedBox(height: LovSpace.xxl),
                if (_busy)
                  Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  )
                else
                  LovEnter(
                    delay: const Duration(milliseconds: 200),
                    child: Text(
                      'Auto-verifies when you finish typing.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: LovSpace.lg),
                Center(
                  child: _secondsLeft > 0
                      ? Text(
                          'Resend code in ${_secondsLeft}s',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        )
                      : TextButton(
                          onPressed: _resending ? null : _resend,
                          child: _resending
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.5),
                                  ),
                                )
                              : const Text('Resend code'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
