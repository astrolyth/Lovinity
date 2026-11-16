import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/hijri_dates.dart';
import '../../../core/widgets/widgets.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_providers.dart';
import 'event_editor_sheet.dart';

/// The couple's shared calendar, in both calendars at once.
///
/// A month grid over Gregorian dates (the grid people navigate by) with the
/// Hijri date shown for the selected day and on Hijri-anchored events, so an
/// Islamic anniversary reads correctly even though it moves against the
/// Gregorian month it happens to land in this year.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime? _selected;
  late DateTime _visibleMonth;
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eventsAsync = ref.watch(calendarEventsProvider);
    final today = DateTime.parse(ref.watch(calendarTodayKeyProvider));

    if (!_initialised) {
      _visibleMonth = DateTime(today.year, today.month);
      _initialised = true;
    }
    final selected = _selected ?? today;

    return LovScaffold(
      title: 'Calendar',
      subtitle: HijriDate(date: selected),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEventEditor(context, ref, initialDate: selected),
        child: const Icon(Icons.add),
      ),
      child: eventsAsync.when(
        loading: () => const _CalendarSkeleton(),
        error: (e, _) => Center(
          child: Text('Could not load the calendar',
              style: theme.textTheme.bodyMedium),
        ),
        data: (events) {
          final onSelected = eventsOnDate(events: events, date: selected);
          final upcoming = resolveUpcoming(events: events, today: today);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
            children: [
              _MonthHeader(
                month: _visibleMonth,
                onPrevious: () => setState(() {
                  _visibleMonth =
                      DateTime(_visibleMonth.year, _visibleMonth.month - 1);
                }),
                onNext: () => setState(() {
                  _visibleMonth =
                      DateTime(_visibleMonth.year, _visibleMonth.month + 1);
                }),
              ),
              const SizedBox(height: LovSpace.md),
              _MonthGrid(
                month: _visibleMonth,
                today: today,
                selected: selected,
                events: events,
                onSelect: (d) => setState(() => _selected = d),
              ),
              const SizedBox(height: LovSpace.xl),
              LovSectionHeader(
                title: DateFormat('EEEE, d MMMM').format(selected),
                subtitle: formatHijri(hijriFromGregorian(selected)),
              ),
              if (onSelected.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
                  child: Text(
                    'Nothing on this day.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                )
              else
                LovStagger(
                  children: [
                    for (final u in onSelected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: LovSpace.sm),
                        child: _EventTile(upcoming: u, today: today),
                      ),
                  ],
                ),
              const SizedBox(height: LovSpace.xl),
              const LovSectionHeader(title: 'Coming up'),
              if (upcoming.isEmpty)
                const LovEmpty(
                  icon: Icons.event_outlined,
                  title: 'No events yet',
                  description:
                      'Add anniversaries, birthdays and Islamic dates you '
                      'both want to remember.',
                )
              else
                for (final u in upcoming.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: LovSpace.sm),
                    child: _EventTile(upcoming: u, today: today),
                  ),
              const SizedBox(height: LovSpace.xxxl),
            ],
          );
        },
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The Hijri span of a Gregorian month: a Gregorian month almost always
    // straddles two Hijri months, so naming just one would be wrong for most
    // of the grid below.
    final first = hijriFromGregorian(DateTime(month.year, month.month, 1));
    final last = hijriFromGregorian(
        DateTime(month.year, month.month + 1, 0));
    final hijriSpan = first.month == last.month
        ? formatHijri(first).split(' ').skip(1).join(' ')
        : '${_monthOnly(first)} – ${_monthOnly(last)}';

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                DateFormat('MMMM y').format(month),
                style: theme.textTheme.titleMedium,
              ),
              Text(
                hijriSpan,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
      ],
    );
  }

  String _monthOnly(HijriDay h) => formatHijri(h).split(' ').skip(1).join(' ');
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.events,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday-first grid: DateTime.weekday is 1=Mon..7=Sun.
    final leadingBlanks = firstOfMonth.weekday - 1;

    return Column(
      children: [
        Row(
          children: [
            for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: LovSpace.xs),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) return const SizedBox.shrink();
            final day = DateTime(
                month.year, month.month, index - leadingBlanks + 1);
            return _DayCell(
              day: day,
              isToday: _sameDay(day, today),
              isSelected: _sameDay(day, selected),
              hasEvents: eventsOnDate(events: events, date: day).isNotEmpty,
              onTap: () => onSelect(day),
            );
          },
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: LovMotion.standard,
          curve: LovMotion.enter,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : Colors.transparent,
            shape: BoxShape.circle,
            border: !isSelected && isToday
                ? Border.all(color: scheme.primary, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: hasEvents
                      ? (isSelected ? scheme.onPrimary : scheme.secondary)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.upcoming, required this.today});

  final UpcomingEvent upcoming;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final event = upcoming.event;
    final days = upcoming.daysFrom(today);

    return LovCard(
      variant: LovCardVariant.plain,
      onTap: () => showEventEditor(context, ref, existing: event),
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.lg,
        vertical: LovSpace.md,
      ),
      child: Row(
        children: [
          Icon(_iconFor(event.kind),
              size: 20, color: theme.colorScheme.secondary),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  _subtitle(event),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _relative(days),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the Hijri date for Hijri-anchored events, since that is the date
  /// the event is actually pinned to — its Gregorian day is just where it
  /// happens to fall this year.
  String _subtitle(CalendarEvent event) {
    final anchor = event.hijriAnchor;
    final parts = <String>[
      if (anchor != null)
        formatHijri(HijriDay(hijriFromGregorian(upcoming.date).year,
            anchor.month, anchor.day))
      else
        DateFormat('d MMM y').format(upcoming.date),
      if (!event.allDay) DateFormat.jm().format(event.startsAt.toLocal()),
      if (event.repeats) 'repeats',
    ];
    return parts.join(' · ');
  }

  String _relative(int days) {
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days < 30) return 'in ${days}d';
    if (days < 365) return 'in ${(days / 30).round()}mo';
    return 'in ${(days / 365).round()}y';
  }

  IconData _iconFor(CalendarEventKind kind) => switch (kind) {
        CalendarEventKind.anniversary => Icons.favorite_rounded,
        CalendarEventKind.birthday => Icons.cake_outlined,
        CalendarEventKind.islamic => Icons.star_outline_rounded,
        CalendarEventKind.event => Icons.event_outlined,
      };
}

class _CalendarSkeleton extends StatelessWidget {
  const _CalendarSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: LovSpace.lg),
      child: Column(
        children: [
          LovShimmerBox(height: 40, radius: LovRadius.md),
          SizedBox(height: LovSpace.md),
          LovShimmerBox(height: 260, radius: LovRadius.lg),
          SizedBox(height: LovSpace.lg),
          LovShimmerBox(height: 64, radius: LovRadius.lg),
          SizedBox(height: LovSpace.sm),
          LovShimmerBox(height: 64, radius: LovRadius.lg),
        ],
      ),
    );
  }
}
