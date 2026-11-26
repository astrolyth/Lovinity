import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../../core/widgets/widgets.dart' show LovInlineError;
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../domain/onboarding_providers.dart';

/// Three short steps: your name, which one you are, and when Asr begins.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  int _step = 0;
  String? _gender;
  String _madhhab = 'shafi';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
    0 => _name.text.trim().isNotEmpty,
    1 => _gender != null,
    _ => !_saving,
  };

  void _next() {
    if (_step < 2) {
      FocusScope.of(context).unfocus();
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session == null || _gender == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(onboardingRepositoryProvider)
          .saveProfile(
            userId: session.user.id,
            displayName: _name.text.trim(),
            gender: _gender!,
            madhhab: _madhhab,
          );
      ref.invalidate(ownProfileProvider);
      if (mounted) context.go('/pair');
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final pad = MediaQuery.paddingOf(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final name = _name.text.trim();
    final steps = [
      _Step(
        eyebrow: "Let's begin",
        title: 'What should we call you?',
        body: 'Only your spouse will see it.',
        child: TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.givenName],
          decoration: const InputDecoration(hintText: 'Your first name'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_canContinue) _next();
          },
        ),
      ),
      _Step(
        eyebrow: 'Assalamu alaikum, ${name.split(' ').first}',
        title: 'Which one are you?',
        body:
            'This shapes a few screens: the wife gets the cycle tracker, the '
            'husband gets gentle care tips.',
        child: Column(
          children: [
            _RoleCard(
              label: 'Husband',
              tint: p.accent,
              soft: p.accentSoft,
              selected: _gender == 'male',
              onTap: () => setState(() => _gender = 'male'),
            ),
            const SizedBox(height: 10),
            _RoleCard(
              label: 'Wife',
              tint: p.partner,
              soft: p.partnerSoft,
              selected: _gender == 'female',
              onTap: () => setState(() => _gender = 'female'),
            ),
          ],
        ),
      ),
      _Step(
        eyebrow: 'Prayer times',
        title: 'When does Asr begin for you?',
        body:
            'Prayer times are worked out on your phone; your location stays '
            'private. You can change this later in Settings.',
        child: LovSegmented<String>(
          values: const ['shafi', 'hanafi'],
          labelOf: (v) => v == 'shafi' ? 'Standard' : 'Hanafi',
          selected: _madhhab,
          onChanged: (v) => setState(() => _madhhab = v),
        ),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: LovAmbient()),
            Padding(
              padding: EdgeInsets.fromLTRB(16, pad.top + 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Opacity(
                        opacity: _step == 0 ? 0 : 1,
                        child: LovIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          label: 'Back',
                          onTap: _step == 0
                              ? null
                              : () => setState(() => _step--),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Semantics(
                          label: 'Step ${_step + 1} of 3',
                          child: Row(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(width: 6),
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 400),
                                    curve: lovSpring,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: i <= _step ? p.accent : p.line,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${_step + 1}/3',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, color: p.muted),
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(4, 36, 4, 0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 450),
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: SlideTransition(
                            position:
                                Tween(
                                  begin: const Offset(.08, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(parent: a, curve: lovSpring),
                                ),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: steps[_step],
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LovInlineError(message: _error!),
                    ),
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: 20 + (inset > 0 ? inset : pad.bottom),
                    ),
                    child: LovPrimaryButton(
                      label: _step < 2 ? 'Continue' : 'Finish',
                      loading: _saving,
                      onPressed: _canContinue ? _next : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.child,
  });
  final String eyebrow;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LovEyebrow(eyebrow),
      const SizedBox(height: 10),
      Text(title, style: lovDisplay(context, size: 32, height: 1.1)),
      const SizedBox(height: 10),
      Text(
        body,
        style: TextStyle(fontSize: 15, height: 1.5, color: context.lov.muted),
      ),
      const SizedBox(height: 26),
      child,
    ],
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.label,
    required this.tint,
    required this.soft,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final Color tint;
  final Color soft;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        haptic: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected ? tint.withValues(alpha: .08) : p.surface,
            border: Border.all(
              color: selected ? tint : p.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                child: Icon(Icons.person_outline_rounded, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.check_circle_rounded, color: tint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
