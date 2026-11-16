import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/date_repository.dart';
import '../domain/date_providers.dart';

/// Halal date ideas — at home, out, or apart.
class DatesScreen extends ConsumerWidget {
  const DatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ideasAsync = ref.watch(dateIdeasProvider);
    final entries = ref.watch(dateEntriesProvider);
    final planned = ref.watch(plannedDatesProvider);
    final filter = ref.watch(dateSettingFilterProvider);

    return LovScaffold(
      title: 'Date ideas',
      subtitle: Text(planned.isEmpty
          ? 'Something to look forward to'
          : '${planned.length} planned'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: ideasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load ideas',
              style: theme.textTheme.bodyMedium),
        ),
        data: (_) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: LovSpace.md),
              child: Row(
                children: [
                  for (final s in DateSetting.values) ...[
                    ChoiceChip(
                      label: Text(s.label),
                      selected: filter == s,
                      onSelected: (_) => ref
                          .read(dateSettingFilterProvider.notifier)
                          .toggle(s),
                    ),
                    const SizedBox(width: LovSpace.sm),
                  ],
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const LovEmpty(
                      icon: Icons.favorite_border,
                      title: 'No ideas here',
                      description: 'Try another setting.',
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: LovSpace.md),
                        child: _IdeaCard(entry: entries[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaCard extends ConsumerWidget {
  const _IdeaCard({required this.entry});

  final DateIdeaEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final idea = entry.idea;
    final save = entry.save;

    return LovCard(
      variant: LovCardVariant.plain,
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(idea.title, style: theme.textTheme.titleSmall),
              ),
              IconButton(
                icon: Icon(
                  entry.isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 20,
                  color: entry.isSaved
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: () => _toggleSave(ref),
              ),
            ],
          ),
          Text(
            idea.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: LovSpace.sm),
          Wrap(
            spacing: LovSpace.sm,
            children: [
              _Tag(label: idea.setting.label),
              _Tag(label: idea.isFree ? 'Free' : idea.costBand),
              _Tag(label: '${idea.effort} effort'),
            ],
          ),
          if (save != null && entry.isPlanned) ...[
            const SizedBox(height: LovSpace.sm),
            Row(
              children: [
                Icon(Icons.event_available,
                    size: 16, color: theme.colorScheme.secondary),
                const SizedBox(width: LovSpace.xs),
                Text(
                  'Planned for '
                  '${DateFormat('EEE d MMM').format(save.plannedFor!)}',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => ref
                      .read(dateRepositoryProvider)
                      .markDone(saveId: save.id),
                  child: const Text('We did it'),
                ),
              ],
            ),
          ] else if (save != null && entry.isDone) ...[
            const SizedBox(height: LovSpace.sm),
            Row(
              children: [
                Icon(Icons.check_circle,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: LovSpace.xs),
                Text('Done together', style: theme.textTheme.labelSmall),
              ],
            ),
          ] else if (save != null) ...[
            const SizedBox(height: LovSpace.sm),
            TextButton(
              onPressed: () => _pickDate(context, ref, save.id),
              child: const Text('Plan a day'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleSave(WidgetRef ref) async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;
    final repo = ref.read(dateRepositoryProvider);
    final save = entry.save;
    if (save != null) {
      await repo.unsave(saveId: save.id);
    } else {
      await repo.save(
        coupleId: couple.id,
        ideaId: entry.idea.id,
        userId: session.user.id,
      );
    }
  }

  Future<void> _pickDate(
      BuildContext context, WidgetRef ref, String saveId) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    await ref.read(dateRepositoryProvider).plan(
          saveId: saveId,
          plannedFor: picked,
        );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LovSpace.sm, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LovRadius.sm),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
