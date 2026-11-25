// lib/features/settings/presentation/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crypto/crypto_providers.dart';
import '../../../core/crypto/safety_number.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../auth/domain/auth_controller.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../home/domain/home_providers.dart';
import '../domain/settings_providers.dart';

const _methodLabels = {
  'muslim_world_league': 'Muslim World League',
  'egyptian': 'Egyptian',
  'karachi': 'Karachi',
  'umm_al_qura': 'Umm al-Qura',
  'dubai': 'Dubai',
  'moon_sighting_committee': 'Moonsighting',
  'north_america': 'ISNA',
  'kuwait': 'Kuwait',
  'qatar': 'Qatar',
  'singapore': 'Singapore',
  'turkey': 'Turkey',
  'tehran': 'Tehran',
};

/// Theme names and moods shown in the picker (design: Settings → Theme).
const lovThemeMeta = {
  LovThemeId.midnight: ('Midnight Gold', 'Black and gold'),
  LovThemeId.emerald: ('Emerald Masjid', 'Deep green, gilded'),
  LovThemeId.lapis: ('Lapis Night', 'Navy and sky'),
  LovThemeId.rose: ('Rose Noir', 'Ink and blush'),
  LovThemeId.desert: ('Desert Ember', 'Warm dusk'),
  LovThemeId.sandstone: ('Sandstone Day', 'Light, warm paper'),
  LovThemeId.pearl: ('Pearl Mint', 'Light and fresh'),
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    // Derive from the profile rather than also watching isWifeProvider:
    // watching an async provider and a sync provider derived from it in the
    // same build re-enters and throws "setState during build".
    final profile = ref.watch(ownProfileProvider).asData?.value;
    final spouse = ref.watch(spouseProfileProvider).asData?.value;
    final isWife = profile?.gender == 'female';
    final madhhab = profile?.madhhab ?? 'shafi';
    final shareDefault = ref.watch(shareCycleByDefaultProvider);
    final theme = ref.watch(themeProvider);
    final name = profile?.displayName.trim() ?? '';
    final spouseName = spouse?.displayName.trim() ?? '';
    final role = switch (profile?.gender) {
      'female' => 'Wife',
      'male' => 'Husband',
      _ => null,
    };

    Future<void> setPref(String key, bool v) async {
      final session = ref.read(authSessionProvider).asData?.value;
      if (session == null) return;
      final current = ref.read(preferencesProvider).asData?.value ?? const {};
      await ref
          .read(preferencesRepositoryProvider)
          .setKey(
            userId: session.user.id,
            key: key,
            value: v,
            current: Map<String, dynamic>.from(current),
          );
    }

    return LovPage(
      title: 'Settings',
      slivers: [
        SliverToBoxAdapter(
          child: LovRise(
            child: _Group(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      LovAvatar(initial: name, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? 'You' : name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                ?role,
                                if (spouseName.isNotEmpty)
                                  'paired with $spouseName',
                              ].join(' · '),
                              style: TextStyle(fontSize: 13, color: p.muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editProfile(context, ref, name),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const _Label('Your space'),
        SliverToBoxAdapter(
          child: _Group(
            children: [
              _Row(
                leading: LovAvatar(
                  initial: spouseName,
                  size: 28,
                  partner: true,
                ),
                label: spouseName.isEmpty ? 'Your spouse' : spouseName,
                value: 'Paired',
                onTap: () => context.push('/home/us'),
              ),
              _Row(
                leading: Icon(Icons.lock_outline_rounded, color: p.accent),
                label: 'Encryption',
                value: 'Verify',
                chevron: true,
                onTap: () => _verifyEncryption(context, spouseName),
              ),
            ],
          ),
        ),
        const _Label('Prayer'),
        SliverToBoxAdapter(
          child: _Group(
            children: [
              _Row(
                label: 'Calculation method',
                value:
                    _methodLabels[profile?.calcMethod] ??
                    _methodLabels['muslim_world_league']!,
                chevron: true,
                onTap: () => _pickMethod(context, ref, profile?.calcMethod),
              ),
              _Row(
                label: 'Asr time',
                trailing: SizedBox(
                  width: 190,
                  child: LovSegmented<String>(
                    values: const ['shafi', 'hanafi'],
                    labelOf: (v) => v == 'shafi' ? 'Standard' : 'Hanafi',
                    selected: madhhab,
                    height: 40,
                    onChanged: (v) async {
                      if (profile == null) return;
                      final session = ref
                          .read(authSessionProvider)
                          .asData
                          ?.value;
                      if (session == null) return;
                      await ref
                          .read(profileRepositoryProvider)
                          .updateMadhhab(userId: session.user.id, madhhab: v);
                      // Recompute prayer times (and the cycle max-duration hint).
                      ref.invalidate(ownProfileProvider);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const _Label('Appearance'),
        SliverToBoxAdapter(
          child: _Group(
            children: [
              _Row(
                leading: _Swatch(theme: theme),
                label: 'Theme',
                hint: '${lovThemeMeta[theme]!.$1} · ${lovThemeMeta[theme]!.$2}',
                chevron: true,
                onTap: () => _openThemes(context),
              ),
            ],
          ),
        ),
        const _Label('Notifications'),
        SliverToBoxAdapter(
          child: _Group(
            children: [
              _Row(
                label: 'Adhan reminders',
                hint: 'A gentle alert at each prayer time.',
                trailing: Switch(
                  value: ref.watch(adhanRemindersProvider),
                  onChanged: (v) async {
                    await setPref('adhan_reminders', v);
                    ref.invalidate(preferencesProvider);
                  },
                ),
              ),
              _Row(
                label:
                    'Tell me when ${spouseName.isEmpty ? 'my spouse' : spouseName} prays',
                trailing: Switch(
                  value: ref.watch(partnerPrayerAlertsProvider),
                  onChanged: (v) async {
                    await setPref('partner_prayer_alerts', v);
                    ref.invalidate(preferencesProvider);
                  },
                ),
              ),
              _Row(
                label: 'Hourly moment reminders',
                hint: 'A nudge each hour (9am–10pm) to share a moment.',
                trailing: Switch(
                  value: ref.watch(momentNudgesProvider),
                  onChanged: (v) async {
                    await setPref('moment_nudges', v);
                    ref.invalidate(preferencesProvider);
                  },
                ),
              ),
            ],
          ),
        ),
        if (isWife) ...[
          const _Label('Privacy'),
          SliverToBoxAdapter(
            child: _Group(
              children: [
                _Row(
                  label: 'Share cycle with spouse by default',
                  hint:
                      'When off, your spouse only sees that your score is resting.',
                  trailing: Switch(
                    value: shareDefault,
                    onChanged: (v) async {
                      await setPref('share_cycle_default', v);
                      // Apply to an active cycle immediately, if any.
                      final active = ref.read(activeCycleProvider);
                      if (active != null) {
                        await ref
                            .read(cycleRepositoryProvider)
                            .setVisibility(
                              recordId: active.id,
                              visibility: v ? 'shared' : 'private',
                            );
                      }
                      ref.invalidate(preferencesProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        const _Label('Security'),
        SliverToBoxAdapter(
          child: _Group(
            children: [
              _Row(
                leading: Icon(Icons.face_rounded, color: p.accent),
                label: 'Lock with Face ID',
                hint: 'Ask for Face ID or your passcode when you come back.',
                trailing: Switch(
                  value: ref.watch(appLockProvider),
                  onChanged: (v) async {
                    final ok = await ref.read(appLockProvider.notifier).set(v);
                    if (!ok && context.mounted) {
                      showLovToast(
                        context,
                        "Couldn't confirm it's you",
                        icon: Icons.error_outline_rounded,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: _Group(
            margin: const EdgeInsets.fromLTRB(16, 26, 16, 0),
            children: [
              _Row(
                label: 'About Lovinity',
                chevron: true,
                onTap: () => context.push('/home/settings/about'),
              ),
              _Row(
                label: 'Content sources',
                hint: 'Duas & adhkar: fitrahive/dua-dhikr (MIT)',
                chevron: true,
                onTap: () => showLicensePage(context: context),
              ),
              _Row(
                label: 'Sign out',
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _editProfile(BuildContext context, WidgetRef ref, String name) {
    final controller = TextEditingController(text: name);
    showLovSheet<void>(
      context,
      title: 'Edit profile',
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: StatefulBuilder(
          builder: (sheet, setState) {
            final draft = controller.text.trim();
            Future<void> save() async {
              final self = ref.read(authSessionProvider).asData?.value;
              if (self == null || draft.isEmpty) return;
              final host = Navigator.of(sheet).context;
              try {
                await ref
                    .read(profileRepositoryProvider)
                    .updateDisplayName(userId: self.user.id, name: draft);
                ref.invalidate(ownProfileProvider);
                if (sheet.mounted) Navigator.of(sheet).pop();
                if (host.mounted) showLovToast(host, 'Profile updated');
              } catch (_) {
                if (sheet.mounted) {
                  showLovToast(
                    sheet,
                    "Couldn't save your name",
                    icon: Icons.error_outline_rounded,
                  );
                }
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => save(),
                ),
                const SizedBox(height: 12),
                LovPrimaryButton(
                  label: 'Save',
                  onPressed: draft.isEmpty ? null : save,
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _verifyEncryption(BuildContext context, String spouseName) {
    final who = spouseName.isEmpty ? 'your spouse' : spouseName;
    showLovSheet<void>(
      context,
      title: 'Verify encryption',
      builder: (sheet) => Consumer(
        builder: (sheet, ref, _) {
          final p = sheet.lov;
          final number = ref.watch(safetyNumberProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Open this screen on $who\'s phone. If the numbers match, '
                'only the two of you can read your chat.',
                style: TextStyle(fontSize: 14, height: 1.5, color: p.text2),
              ),
              const SizedBox(height: 18),
              number.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Text(
                  "Couldn't load the safety number.",
                  style: TextStyle(color: p.muted),
                ),
                data: (n) => n == null
                    ? Text(
                        'Send $who a message first, then come back to compare.',
                        style: TextStyle(color: p.muted),
                      )
                    : Semantics(
                        label: 'Safety number ${n.split('').join(' ')}',
                        excludeSemantics: true,
                        child: GridView.count(
                          crossAxisCount: 4,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.4,
                          children: [
                            for (var i = 0; i < 12; i++)
                              LovRise(
                                delay: Duration(milliseconds: 30 * i),
                                child: Center(
                                  child: Text(
                                    n.substring(i * 5, i * 5 + 5),
                                    style: lovDisplay(sheet, size: 18),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  void _pickMethod(BuildContext context, WidgetRef ref, String? current) {
    showLovSheet<void>(
      context,
      title: 'Calculation method',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final MapEntry(key: k, value: label) in _methodLabels.entries)
            LovSheetRow(
              icon: k == (current ?? 'muslim_world_league')
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              title: label,
              onTap: () async {
                final self = ref.read(authSessionProvider).asData?.value;
                Navigator.of(sheet).pop();
                if (self == null) return;
                try {
                  await ref
                      .read(profileRepositoryProvider)
                      .updateCalcMethod(userId: self.user.id, method: k);
                  // Recompute prayer times.
                  ref.invalidate(ownProfileProvider);
                } catch (_) {
                  if (context.mounted) {
                    showLovToast(
                      context,
                      "Couldn't change the method",
                      icon: Icons.error_outline_rounded,
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    showLovSheet<void>(
      context,
      title: 'Sign out?',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your space stays as it is. Sign in again any time with your email.',
            style: TextStyle(fontSize: 15, height: 1.5, color: p.muted),
          ),
          const SizedBox(height: 22),
          LovQuietButton(
            label: 'Sign out',
            onPressed: () {
              Navigator.pop(sheet);
              ref.read(signOutProvider)();
            },
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(sheet),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _openThemes(BuildContext context) {
    showLovSheet<void>(
      context,
      title: 'Theme',
      builder: (sheet) => const _ThemePicker(),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeProvider);
    final p = context.lov;
    Widget grid(List<LovThemeId> ids) => GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      mainAxisExtent: 64,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final id in ids)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: id == current,
            button: true,
            label: '${lovThemeMeta[id]!.$1}, ${lovThemeMeta[id]!.$2}',
            excludeSemantics: true,
            child: LovPressable(
              onTap: () => ref.read(themeProvider.notifier).select(id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: id == current
                      ? p.accent.withValues(alpha: .08)
                      : p.hi.withValues(alpha: .03),
                  border: Border.all(color: id == current ? p.accent : p.line),
                  boxShadow: id == current
                      ? [
                          BoxShadow(
                            color: p.accent.withValues(alpha: .14),
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    _Swatch(theme: id, selected: id == current),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            lovThemeMeta[id]!.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            lovThemeMeta[id]!.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    Widget label(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: LovEyebrow(t),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ThemePreview(),
        label('Dark'),
        grid([
          for (final t in LovThemeId.values)
            if (t.palette.isDark) t,
        ]),
        label('Light'),
        grid([
          for (final t in LovThemeId.values)
            if (!t.palette.isDark) t,
        ]),
        const SizedBox(height: 20),
        LovQuietButton(label: 'Done', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

/// A miniature Home in the chosen theme, so the change is visible at once.
class _ThemePreview extends ConsumerWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final self = ref.watch(ownProfileProvider).asData?.value?.displayName ?? '';
    final spouse =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ?? '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: 148,
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.line),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -60,
            width: 220,
            height: 170,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    p.accent.withValues(alpha: .2),
                    p.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -50,
            top: -30,
            width: 160,
            height: 130,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    p.partner.withValues(alpha: .14),
                    p.partner.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 24,
                  child: Stack(
                    children: [
                      LovAvatar(initial: self, size: 24),
                      Positioned(
                        left: 10,
                        child: LovAvatar(
                          initial: spouse,
                          size: 24,
                          partner: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'You and ${spouse.isEmpty ? 'yours' : spouse.split(' ').first}',
                  style: lovDisplay(context, size: 15),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              height: 68,
              padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.dark_mode_outlined, color: p.accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const LovEyebrow('Next prayer'),
                        Text('Maghrib', style: lovDisplay(context, size: 18)),
                      ],
                    ),
                  ),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '1:42:08',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: p.onAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A theme's bg / accent / partner as a small tile.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.theme, this.selected = false});
  final LovThemeId theme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = theme.palette;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.line),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 18, color: t.accent)
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _dot(t.accent),
                const SizedBox(width: 3),
                _dot(t.partner),
              ],
            ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
      child: LovEyebrow(text),
    ),
  );
}

/// Rounded grouped list (iOS settings style).
class _Group extends StatelessWidget {
  const _Group({
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });
  final List<Widget> children;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: p.surface2),
            c,
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    this.leading,
    this.value,
    this.hint,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });
  final String label;
  final Widget? leading;
  final String? value;
  final String? hint;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15)),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hint!,
                        style: TextStyle(fontSize: 12.5, color: p.muted),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Text(value!, style: TextStyle(fontSize: 14, color: p.muted)),
            ?trailing,
            if (chevron)
              Icon(Icons.chevron_right_rounded, color: p.faint, size: 20),
          ],
        ),
      ),
    );
  }
}
