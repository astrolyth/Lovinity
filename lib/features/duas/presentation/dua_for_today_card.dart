import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/adhkar_providers.dart';
import '../domain/dua_suggestions.dart';
import '../domain/suggestion_providers.dart';
import 'library_dua_sheet.dart';

/// "Ameen together": who has said Ameen today, and the button to say yours.
class _AmeenRow extends ConsumerWidget {
  const _AmeenRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final self = ref.watch(authSessionProvider).asData?.value?.user.id;
    final couple = ref.watch(currentCoupleProvider).asData?.value;
    final spouseId = self == null ? null : couple?.spouseOf(self);
    final ownName =
        ref.watch(ownProfileProvider).asData?.value?.displayName ?? 'You';
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ??
        'Your spouse';
    final said = ref.watch(todayAmeensProvider).asData?.value ?? const {};
    final mine = said.containsKey(self), theirs = said.containsKey(spouseId);
    final line = switch ((mine, theirs)) {
      (true, true) => 'You both said Ameen',
      (false, true) =>
        '$spouseName said Ameen at ${DateFormat.jm().format(said[spouseId]!.toLocal())}',
      (true, false) => 'You said Ameen. $spouseName will see it',
      _ => 'Say Ameen together',
    };
    final ready = self != null && couple != null &&
        ref.watch(adhkarTodayKeyProvider) != null;

    return Row(
      children: [
        if (theirs)
          LovAvatar(initial: spouseName, size: 30, partner: true),
        if (mine)
          Transform.translate(
            offset: Offset(theirs ? -8 : 0, 0),
            child: LovAvatar(initial: ownName, size: 30),
          ),
        if (mine || theirs) const SizedBox(width: 8),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              line,
              key: ValueKey(line),
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
          ),
        ),
        if (!mine)
          FilledButton(
            onPressed: !ready
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    ref
                        .read(ameenRepositoryProvider)
                        .say(
                          coupleId: couple.id,
                          userId: self,
                          day: ref.read(adhkarTodayKeyProvider)!,
                        )
                        .catchError((_) {
                          if (context.mounted) {
                            showLovToast(
                              context,
                              "Couldn't send your Ameen",
                              icon: Icons.error_outline_rounded,
                            );
                          }
                        });
                  },
            child: const Text('Ameen'),
          ),
      ],
    );
  }
}

class DuaForTodayCard extends ConsumerWidget {
  const DuaForTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(duaSuggestionsProvider);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final mood = ref.watch(todayMoodProvider).asData?.value;
    final ready = ref.watch(adhkarTodayKeyProvider) != null;
    final s = suggestions.first;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return LovCard(
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LovEyebrow('Dua for today · for the two of you'),
          const SizedBox(height: LovSpace.md),
          InkWell(
            onTap: () => showLibraryDuaSheet(context, s.dua),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.dua.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: LovSpace.xs),
                Text(
                  s.reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: LovSpace.xs),
                Text(
                  s.dua.translation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: LovSpace.md),
          Wrap(
            spacing: LovSpace.xs,
            children: [
              for (final m in Mood.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: mood == m,
                  onSelected: ready
                      ? (_) => ref
                            .read(todayMoodProvider.notifier)
                            .set(mood == m ? null : m)
                      : null,
                ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          const _AmeenRow(),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push('/home/tasbih'),
              child: const Text('Tasbih together'),
            ),
          ),
        ],
      ),
    );
  }
}
