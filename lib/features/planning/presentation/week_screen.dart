import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../auth/domain/auth_controller.dart';
import '../../calendar/data/calendar_repository.dart';
import '../../calendar/domain/calendar_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/meal_plan_repository.dart';
import '../domain/planning_providers.dart';
import 'week_sheets.dart';

/// "This week": pick a day to see its plans and dinner; the shared grocery
/// list sits underneath. Each section opens its full screen.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key});

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  late DateTime _day = _today();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final self = ref.watch(
      authSessionProvider.select((s) => s.asData?.value?.user.id),
    );
    final events = ref.watch(calendarEventsProvider).asData?.value ?? const [];
    final today = _today();
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final dayEvents = eventsOnDate(events: events, date: _day);
    final plan = ref.watch(viewedMealPlanProvider);
    final dinner = plan?.mealFor(_day.weekday - 1, MealSlot.dinner);
    final groceries = ref.watch(activeGroceryItemsProvider);
    final left = groceries.where((g) => !g.checked).length;
    final spouseId = self == null
        ? null
        : ref.watch(currentCoupleProvider).asData?.value?.spouseOf(self);
    final ownName =
        ref.watch(ownProfileProvider).asData?.value?.displayName ?? 'You';
    final spouseName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName ??
        'Spouse';
    // Together and "you" plans are gold; the spouse's are rose.
    Color colorOf(CalendarEvent e) =>
        e.assigneeId != null && e.assigneeId != self ? p.partner : p.accent;
    final cook = cookLabel(
      plan?.slots[dinnerCookKey(_day.weekday - 1)],
      self: self,
      spouseName: spouseName,
    );

    return LovPage(
      title: 'This week',
      action: LovIconButton(
        icon: Icons.add_rounded,
        label: 'New plan',
        onTap: () => showNewPlanSheet(context, week: week, day: _day),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final d in week)
                  Expanded(
                    child: _Day(
                      date: d,
                      selected: d == _day,
                      dots: [
                        for (final e in eventsOnDate(
                          events: events,
                          date: d,
                        ).take(3))
                          colorOf(e.event),
                      ],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _day = d);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: LovSurface(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              onTap: () => context.push('/home/calendar'),
              child: dayEvents.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Nothing planned for ${DateFormat.EEEE().format(_day)}.',
                        style: TextStyle(fontSize: 14, color: p.muted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final (i, e) in dayEvents.indexed) ...[
                          if (i > 0) Divider(height: 1, color: p.surface2),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colorOf(e.event),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.event.title,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          e.event.allDay
                                              ? 'All day'
                                              : DateFormat.jm().format(
                                                  e.event.startsAt.toLocal(),
                                                ),
                                          if (e.event.assigneeId == self)
                                            'You'
                                          else if (e.event.assigneeId != null)
                                            spouseName,
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: p.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
        _Label(
          'Dinner · ${DateFormat.EEEE().format(_day)}',
          action: 'Plan meals',
          onAction: () => context.push('/home/plan'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LovSurface(
              radius: 20,
              padding: const EdgeInsets.all(16),
              onTap: () => showDinnerSheet(context, day: _day),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: p.surface2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.restaurant_outlined, color: p.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dinner?.trim().isNotEmpty == true
                              ? dinner!
                              : 'Not planned yet',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dinner?.trim().isNotEmpty == true
                              ? cook ?? 'From your week plan'
                              : 'Pick something together',
                          style: TextStyle(fontSize: 12, color: p.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.faint),
                ],
              ),
            ),
          ),
        ),
        _Label(
          'Groceries',
          trailing: groceries.isEmpty ? null : '$left left',
          action: 'Open list',
          onAction: () => context.push('/home/groceries'),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LovSurface(
              radius: 20,
              padding: EdgeInsets.zero,
              clip: true,
              child: groceries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Your shared list is empty.',
                        style: TextStyle(fontSize: 14, color: p.muted),
                      ),
                    )
                  : Column(
                      children: [
                        for (final (i, g) in groceries.take(8).indexed) ...[
                          if (i > 0) Divider(height: 1, color: p.surface2),
                          CheckboxListTile(
                            value: g.checked,
                            controlAffinity: ListTileControlAffinity.leading,
                            // Who's buying it; tap to hand it to the other.
                            secondary: Semantics(
                              button: true,
                              label: g.buyer == self
                                  ? 'You are buying it. Tap to give it to $spouseName'
                                  : '$spouseName is buying it. Tap to take it',
                              excludeSemantics: true,
                              child: LovPressable(
                                onTap: self == null || spouseId == null
                                    ? null
                                    : () {
                                        HapticFeedback.selectionClick();
                                        ref
                                            .read(groceryRepositoryProvider)
                                            .setBuyer(
                                              itemId: g.id,
                                              buyerId: g.buyer == self
                                                  ? spouseId
                                                  : self,
                                            )
                                            .catchError((_) {
                                              if (context.mounted) {
                                                showLovToast(
                                                  context,
                                                  "Couldn't update the list",
                                                  icon: Icons
                                                      .error_outline_rounded,
                                                );
                                              }
                                            });
                                      },
                                child: LovAvatar(
                                  initial: g.buyer == self
                                      ? ownName
                                      : spouseName,
                                  size: 28,
                                  partner: g.buyer != self,
                                ),
                              ),
                            ),
                            title: Text(
                              [g.name, ?g.qty].join(' · '),
                              style: TextStyle(
                                fontSize: 15,
                                color: g.checked ? p.faint : p.text,
                                decoration: g.checked
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            onChanged: self == null
                                ? null
                                : (v) => ref
                                      .read(groceryRepositoryProvider)
                                      .setChecked(
                                        itemId: g.id,
                                        userId: self,
                                        checked: v ?? false,
                                      )
                                      .catchError((_) {
                                        if (context.mounted) {
                                          showLovToast(
                                            context,
                                            "Couldn't update the list",
                                            icon: Icons.error_outline_rounded,
                                          );
                                        }
                                      }),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.selected,
    required this.dots,
    required this.onTap,
  });
  final DateTime date;
  final bool selected;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Semantics(
      button: true,
      selected: selected,
      label: DateFormat('EEEE d MMMM').format(date),
      excludeSemantics: true,
      child: LovPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: lovSpring,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? p.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                DateFormat.E().format(date).substring(0, 1),
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? p.onAccent : p.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${date.day}',
                style: lovDisplay(
                  context,
                  size: 18,
                  color: selected ? p.onAccent : p.text,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in dots)
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: selected ? p.onAccent : c,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing, this.action, this.onAction});
  final String text;
  final String? trailing;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 6),
      child: Row(
        children: [
          Expanded(child: LovEyebrow(text)),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, color: context.lov.muted),
            ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}
