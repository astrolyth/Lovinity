import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/pairing_providers.dart';

class JoinTab extends ConsumerStatefulWidget {
  const JoinTab({super.key});

  @override
  ConsumerState<JoinTab> createState() => _JoinTabState();
}

class _JoinTabState extends ConsumerState<JoinTab> {
  final _slots = LovDigitSlotsController();
  bool _busy = false;
  String? _error;

  Future<void> _submit(String code) async {
    if (code.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(pairingRepositoryProvider).acceptInvite(code);
      unawaited(LovHaptics.heartbeats());
    } on AppFailure catch (e) {
      _slots.shake();
      unawaited(LovHaptics.medium());
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      _slots.shake();
      if (mounted) setState(() => _error = 'Could not join. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.lg,
        vertical: LovSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: LovSpace.xl),
          LovEnter(
            child: Center(
              child: LovBreathing(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: theme.colorScheme.onSecondary,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: LovSpace.lg),
          LovEnter(
            delay: const Duration(milliseconds: 80),
            child: Text(
              "Enter your spouse's code",
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: LovSpace.xs),
          LovEnter(
            delay: const Duration(milliseconds: 140),
            child: Text(
              'Six characters. Not case-sensitive.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: LovSpace.xxxl),
          LovEnter(
            delay: const Duration(milliseconds: 220),
            child: LovDigitSlots(
              length: 6,
              mode: LovDigitMode.alphanumericUppercase,
              controller: _slots,
              onCompleted: _submit,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
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
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            LovEnter(
              delay: const Duration(milliseconds: 300),
              child: Text(
                'Joins automatically when you finish typing.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
