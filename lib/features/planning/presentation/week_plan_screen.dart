import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/time/local_day.dart';
import '../../../core/widgets/widgets.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/meal_plan_repository.dart';
import '../domain/planning_providers.dart';

/// The week's meals, one row per day.
class WeekPlanScreen extends ConsumerWidget {
  const WeekPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final week = ref.watch(viewedWeekProvider);
    final offset = ref.watch(plannerWeekOffsetProvider);
    final plansAsync = ref.watch(mealPlansProvider);
    final plan = ref.watch(viewedMealPlanProvider);
    final today = DateTime.parse(ref.watch(currentWeekKeyProvider));

    return LovScaffold(
      title: 'Week plan',
      subtitle: Text(_weekLabel(week, offset)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              ref.read(plannerWeekOffsetProvider.notifier).previous(),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => ref.read(plannerWeekOffsetProvider.notifier).next(),
        ),
      ],
      child: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load the plan',
              style: theme.textTheme.bodyMedium),
        ),
        data: (_) => ListView(
          padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
          children: [
            for (var i = 0; i < weekdayKeys.length; i++)
              _DayRow(
                weekdayIndex: i,
                date: DateTime(week.year, week.month, week.day + i),
                isCurrentWeek: dayKey(week) == dayKey(today),
                plan: plan,
                onEdit: (slot, current) => _editSlot(
                  context,
                  ref,
                  week: week,
                  weekdayIndex: i,
                  slot: slot,
                  current: current,
                ),
              ),
            const SizedBox(height: LovSpace.xxxl),
          ],
        ),
      ),
    );
  }

  String _weekLabel(DateTime week, int offset) {
    final end = DateTime(week.year, week.month, week.day + 6);
    final range =
        '${DateFormat('d MMM').format(week)} – ${DateFormat('d MMM').format(end)}';
    if (offset == 0) return 'This week · $range';
    if (offset == 1) return 'Next week · $range';
    if (offset == -1) return 'Last week · $range';
    return range;
  }

  Future<void> _editSlot(
    BuildContext context,
    WidgetRef ref, {
    required DateTime week,
    required int weekdayIndex,
    required MealSlot slot,
    required String? current,
  }) async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    if (couple == null) return;
    final controller = TextEditingController(text: current ?? '');

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${weekdayLabels[weekdayIndex]} ${slot.label.toLowerCase()}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What are you having?'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    await ref.read(mealPlanRepositoryProvider).setSlot(
          coupleId: couple.id,
          week: week,
          slotKey: mealSlotKey(weekdayIndex, slot),
          value: value,
        );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.weekdayIndex,
    required this.date,
    required this.isCurrentWeek,
    required this.plan,
    required this.onEdit,
  });

  final int weekdayIndex;
  final DateTime date;
  final bool isCurrentWeek;
  final MealPlan? plan;
  final void Function(MealSlot slot, String? current) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: LovSpace.md),
      child: LovCard(
        variant: LovCardVariant.plain,
        padding: const EdgeInsets.all(LovSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  weekdayLabels[weekdayIndex],
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: LovSpace.sm),
                Text(
                  DateFormat('d MMM').format(date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LovSpace.sm),
            for (final slot in MealSlot.values)
              _SlotRow(
                slot: slot,
                value: plan?.mealFor(weekdayIndex, slot),
                onTap: () => onEdit(slot, plan?.mealFor(weekdayIndex, slot)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.value,
    required this.onTap,
  });

  final MealSlot slot;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planned = value != null && value!.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LovSpace.xs),
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: Text(
                slot.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            Expanded(
              child: Text(
                planned ? value! : 'Tap to plan',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: planned
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
