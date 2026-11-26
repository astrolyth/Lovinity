import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/crypto/crypto_providers.dart';
import '../../../core/errors/failures.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/security/face_id_login.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/auth_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Mode { password, otp }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;
  _Mode _mode = _Mode.password;
  bool _obscure = true;
  bool _canFaceId = false;
  bool _rememberFaceId = false;
  late String? _faceIdEmail = ref.read(faceIdLoginProvider).savedEmail;

  @override
  void initState() {
    super.initState();
    ref.read(faceIdLoginProvider).deviceSupports().then((ok) {
      if (mounted) setState(() => _canFaceId = ok);
    });
  }

  /// Signs in with the email + password saved behind Face ID.
  Future<void> _signInWithFaceId() async {
    final faceId = ref.read(faceIdLoginProvider);
    final creds = await faceId.read();
    if (creds == null || !mounted) return; // cancelled
    final (email, password) = creds;
    final repo = ref.read(authRepositoryProvider);
    final register = ref.read(ensureRegisteredProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.signInWithPassword(email: email, password: password);
      await register();
      unawaited(LovHaptics.medium());
    } on AuthFailure catch (e) {
      // The password changed since it was saved: forget it.
      if (e.message.toLowerCase().contains('invalid')) {
        await faceId.clear();
        if (mounted) {
          setState(() {
            _faceIdEmail = null;
            _error =
                'Your password has changed. Sign in with it once to turn '
                'Face ID back on.';
          });
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Read up front: a successful sign-in can navigate away mid-flight.
    final faceId = ref.read(faceIdLoginProvider);
    final register = ref.read(ensureRegisteredProvider);
    final remember = _rememberFaceId;
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithPassword(email: email, password: password);
      if (remember) await faceId.save(email, password);
      await register();
      unawaited(LovHaptics.medium());
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

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendEmailOtp(email);
      if (!mounted) return;
      context.push('/auth/otp?email=${Uri.encodeComponent(email)}');
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final password = _mode == _Mode.password;
    return LovScaffold(
      showAppBar: context.canPop(),
      leading: context.canPop()
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => context.pop(),
            )
          : null,
      padded: true,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 22),
                  LovRise(
                    child: Text(
                      'Welcome back',
                      style: lovDisplay(context, size: 34),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    password
                        ? 'Sign in to your space of two.'
                        : "We'll email you a ${Env.otpLength}-digit code. "
                              'No password to remember.',
                    style: TextStyle(fontSize: 15, height: 1.5, color: p.muted),
                  ),
                  const SizedBox(height: 20),
                  LovSegmented<bool>(
                    values: const [true, false],
                    labelOf: (v) => v ? 'Sign in' : 'Create account',
                    selected: true,
                    onChanged: (v) {
                      if (!v) context.push('/auth/sign-up');
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: password
                        ? TextInputAction.next
                        : TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  if (password) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _signInWithPassword(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    LovInlineError(message: _error!),
                  ],
                  if (password && _canFaceId && _faceIdEmail == null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _rememberFaceId,
                      onChanged: (v) => setState(() => _rememberFaceId = v),
                      title: const Text(
                        'Use Face ID to sign in next time',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  if (password)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push('/auth/forgot-password'),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(height: 18),
                  LovPrimaryButton(
                    label: password ? 'Sign in' : 'Send verification code',
                    height: 56,
                    loading: _busy,
                    onPressed: _busy
                        ? null
                        : (password ? _signInWithPassword : _sendOtp),
                  ),
                  if (_canFaceId && _faceIdEmail != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _signInWithFaceId,
                      icon: const Icon(Icons.face_rounded, size: 20),
                      label: Text('Sign in with Face ID · $_faceIdEmail'),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        Expanded(child: Divider(color: p.line)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(fontSize: 13, color: p.muted),
                          ),
                        ),
                        Expanded(child: Divider(color: p.line)),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _mode = password ? _Mode.otp : _Mode.password;
                      _error = null;
                    }),
                    icon: Icon(
                      password
                          ? Icons.mail_outline_rounded
                          : Icons.key_outlined,
                      size: 18,
                    ),
                    label: Text(
                      password
                          ? 'Email me a code instead'
                          : 'Use password instead',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Signing in creates your secure keys for chat.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: p.muted),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
