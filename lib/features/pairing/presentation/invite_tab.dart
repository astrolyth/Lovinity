import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/errors/failures.dart';
import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../data/pairing_repository.dart';
import '../domain/pairing_providers.dart';

const _inviteTtl = Duration(minutes: 10);

class InviteTab extends ConsumerStatefulWidget {
  const InviteTab({super.key});

  @override
  ConsumerState<InviteTab> createState() => _InviteTabState();
}

class _InviteTabState extends ConsumerState<InviteTab> {
  PairingInvite? _invite;
  String? _error;
  bool _loading = false;
  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final invite =
          await ref.read(pairingRepositoryProvider).createInvite();
      _startTicker(invite.expiresAt);
      unawaited(LovHaptics.selection());
      if (mounted) setState(() => _invite = invite);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create a code. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startTicker(DateTime expiresAt) {
    _ticker?.cancel();
    void tick() {
      final left = expiresAt.difference(DateTime.now());
      if (left.isNegative) {
        if (mounted) {
          setState(() {
            _remaining = Duration.zero;
            _invite = null;
          });
        }
        _ticker?.cancel();
        return;
      }
      if (mounted) setState(() => _remaining = left);
    }

    tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _copy(BuildContext context) async {
    if (_invite == null) return;
    await Clipboard.setData(ClipboardData(text: _invite!.code));
    await LovHaptics.selection();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.lg,
        vertical: LovSpace.xl,
      ),
      child: AnimatedSwitcher(
        duration: LovMotion.gentle,
        switchInCurve: LovMotion.enter,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: invite == null
            ? _EmptyInvite(
                key: const ValueKey('empty'),
                loading: _loading,
                onGenerate: _generate,
                error: _error,
              )
            : _ActiveInvite(
                key: ValueKey(invite.code),
                invite: invite,
                remaining: _remaining,
                remainingLabel: _fmt(_remaining),
                onCopy: () => _copy(context),
                onCancel: () {
                  _ticker?.cancel();
                  setState(() {
                    _invite = null;
                    _remaining = Duration.zero;
                  });
                },
              ),
      ),
    );
  }
}

class _EmptyInvite extends StatelessWidget {
  const _EmptyInvite({
    super.key,
    required this.loading,
    required this.onGenerate,
    required this.error,
  });

  final bool loading;
  final VoidCallback onGenerate;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        const SizedBox(height: LovSpace.xl),
        LovBreathing(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_outline_rounded,
              color: theme.colorScheme.onSecondary,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: LovSpace.lg),
        LovEnter(
          delay: const Duration(milliseconds: 60),
          child: Text(
            'Generate a code',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LovSpace.xs),
        LovEnter(
          delay: const Duration(milliseconds: 120),
          child: Text(
            'One-time. Expires in ten minutes.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LovSpace.xxxl),
        LovEnter(
          delay: const Duration(milliseconds: 180),
          child: LovButton(
            label: 'Generate code',
            icon: Icons.add_rounded,
            onPressed: loading ? null : onGenerate,
            loading: loading,
            expand: true,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: LovSpace.lg),
          LovInlineError(message: error!),
        ],
      ],
    );
  }
}

class _ActiveInvite extends StatelessWidget {
  const _ActiveInvite({
    super.key,
    required this.invite,
    required this.remaining,
    required this.remainingLabel,
    required this.onCopy,
    required this.onCancel,
  });

  final PairingInvite invite;
  final Duration remaining;
  final String remainingLabel;
  final VoidCallback onCopy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrgent = remaining.inSeconds > 0 && remaining.inSeconds < 60;
    final chars = invite.code.split('');

    return Column(
      children: [
        LovEnter(
          child: Text(
            'Share this code',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: LovSpace.md),

        // Code with countdown ring around it
        GestureDetector(
          onTap: onCopy,
          child: CountdownRing(
            remaining: remaining,
            total: _inviteTtl,
            size: 220,
            strokeWidth: 2,
            child: LovBreathing(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < chars.length; i++)
                      LovEnter(
                        delay: Duration(milliseconds: 60 + i * 40),
                        duration: LovMotion.standard,
                        slideFrom: 8,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: Text(
                            chars[i],
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 40,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: LovSpace.md),
        LovEnter(
          delay: const Duration(milliseconds: 320),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 14,
                color: isUrgent
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: LovSpace.xs),
              Text(
                'Expires in $remainingLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isUrgent
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: LovSpace.xxl),
        LovEnter(
          delay: const Duration(milliseconds: 400),
          child: LovCard(
            variant: LovCardVariant.outlined,
            padding: const EdgeInsets.all(LovSpace.xl),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(LovSpace.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(LovRadius.md),
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 800),
                    curve: LovMotion.enter,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: 0.8 + 0.2 * t,
                        child: child,
                      ),
                    ),
                    child: QrImageView(
                      data: 'lovinity://pair?code=${invite.code}',
                      size: 180,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.circle,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.circle,
                        color: Colors.black,
                      ),
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: LovSpace.md),
                Text(
                  'Scan from their device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: LovSpace.lg),
        LovEnter(
          delay: const Duration(milliseconds: 480),
          child: Row(
            children: [
              Expanded(
                child: LovButton(
                  label: 'Copy code',
                  icon: Icons.copy_rounded,
                  variant: LovButtonVariant.outlined,
                  onPressed: onCopy,
                  expand: true,
                ),
              ),
              const SizedBox(width: LovSpace.md),
              Expanded(
                child: LovButton(
                  label: 'Cancel',
                  variant: LovButtonVariant.text,
                  onPressed: onCancel,
                  expand: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
