import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/failures.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../domain/onboarding_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  String? _gender;
  String _madhhab = 'shafi';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session == null || _gender == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(onboardingRepositoryProvider).saveProfile(
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
    final canContinue = _gender != null && _name.text.trim().isNotEmpty && !_saving;
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Your name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          const Text('I am a'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _GenderChip(
              label: 'Man', selected: _gender == 'male',
              onTap: () => setState(() => _gender = 'male'))),
            const SizedBox(width: 12),
            Expanded(child: _GenderChip(
              label: 'Woman', selected: _gender == 'female',
              onTap: () => setState(() => _gender = 'female'))),
          ]),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _madhhab,
            decoration: const InputDecoration(labelText: 'Madhhab'),
            items: const [
              DropdownMenuItem(value: 'shafi', child: Text('Shāfiʿī / other')),
              DropdownMenuItem(value: 'hanafi', child: Text('Ḥanafī')),
            ],
            onChanged: (v) => setState(() => _madhhab = v ?? 'shafi'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            LovInlineError(message: _error!),
          ],
          const Spacer(),
          FilledButton(
            onPressed: canContinue ? _submit : null,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue'),
          ),
        ]),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({required this.label, required this.selected, required this.onTap});
  final String label; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1),
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
        ),
        child: Text(label),
      ),
    );
  }
}
