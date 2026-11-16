import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/time/hijri_dates.dart';
import '../../../core/widgets/widgets.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_providers.dart';

/// Home card showing what's coming up on the shared calendar.
class CalendarCard extends ConsumerWidget {
  const CalendarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = DateTime.parse(ref.watch(calendarTodayKeyProvider));
    final upcoming = ref.watch(upcomingEventsProvider);
    final next = upcoming.isEmpty ? null : upcoming.first;

    return LovCard(
      onTap: () => context.push('/home/calendar'),
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'COMING UP',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          if (next == null)
            Text(
              'Nothing on the calendar yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
          else ...[
            Row(
              children: [
                Icon(
                  _iconFor(next.event.kind),
                  size: 18,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: LovSpace.sm),
                Expanded(
                  child: Text(
                    next.event.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _relative(next.daysFrom(today)),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Both calendars, always — the couple keeps dates in both and the
            // card is the surface most likely to be glanced at rather than read.
            Text(
              '${DateFormat('EEE d MMM').format(next.date)} · '
              '${formatHijri(hijriFromGregorian(next.date))}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (upcoming.length > 1) ...[
              const SizedBox(height: LovSpace.sm),
              Text(
                '+${upcoming.length - 1} more ahead',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ],
      ),
    );
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
