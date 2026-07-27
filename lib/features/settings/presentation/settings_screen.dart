// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/crypto/crypto_providers.dart';
import '../../auth/domain/auth_controller.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../home/domain/home_providers.dart';
import '../domain/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Derive from the profile rather than also watching isWifeProvider:
    // watching an async provider and a sync provider derived from it in the
    // same build re-enters and throws "setState during build".
    final profile = ref.watch(ownProfileProvider).asData?.value;
    final isWife = profile?.gender == 'female';
    final madhhab = profile?.madhhab ?? 'shafi';
    final shareDefault = ref.watch(shareCycleByDefaultProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const _SectionHeader('Profile'),
        ListTile(
          title: const Text('Madhhab'),
          subtitle: const Text('Changes when Asr begins.'),
          trailing: DropdownButton<String>(
            value: madhhab,
            onChanged: profile == null
                ? null
                : (v) async {
                    if (v == null || v == madhhab) return;
                    final session = ref.read(authSessionProvider).asData?.value;
                    if (session == null) return;
                    await ref.read(profileRepositoryProvider).updateMadhhab(
                          userId: session.user.id,
                          madhhab: v,
                        );
                    // Recompute prayer times (and the cycle max-duration hint).
                    ref.invalidate(ownProfileProvider);
                  },
            items: const [
              DropdownMenuItem(value: 'shafi', child: Text('Shāfiʿī / other')),
              DropdownMenuItem(value: 'hanafi', child: Text('Ḥanafī')),
            ],
          ),
        ),
        const _SectionHeader('Privacy & Sharing'),
        if (isWife)
          SwitchListTile(
            title: const Text('Share cycle with spouse by default'),
            subtitle: const Text(
                'When off, your spouse only sees that your score is resting.'),
            value: shareDefault,
            onChanged: (v) async {
              final session = ref.read(authSessionProvider).asData?.value;
              if (session == null) return;
              final current =
                  ref.read(preferencesProvider).asData?.value ?? const {};
              await ref.read(preferencesRepositoryProvider).setKey(
                    userId: session.user.id,
                    key: 'share_cycle_default',
                    value: v,
                    current: Map<String, dynamic>.from(current),
                  );
              // Apply to an active cycle immediately, if any.
              final active = ref.read(activeCycleProvider);
              if (active != null) {
                await ref.read(cycleRepositoryProvider).setVisibility(
                    recordId: active.id,
                    visibility: v ? 'shared' : 'private');
              }
              ref.invalidate(preferencesProvider);
            },
          )
        else
          const ListTile(
            title: Text('Privacy'),
            subtitle: Text('Sharing controls appear here as features are added.'),
          ),
        const _SectionHeader('Notifications'),
        const ListTile(
            title: Text('Reminders'),
            subtitle: Text('Prayer and cycle reminders (coming soon).')),
        const _SectionHeader('Security'),
        const ListTile(
            title: Text('App lock'),
            subtitle: Text('Biometric lock (coming soon).')),
        const _SectionHeader('Account'),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(signOutProvider)(),
        ),
        const _SectionHeader('Support'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About Lovinity'),
          onTap: () => context.push('/home/settings/about'),
        ),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary)),
      );
}
