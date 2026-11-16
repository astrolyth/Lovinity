import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/widgets/widgets.dart';
import '../domain/prayer_log_providers.dart';

const _prayers = [
  Prayer.fajr,
  Prayer.dhuhr,
  Prayer.asr,
  Prayer.maghrib,
  Prayer.isha,
];

/// A row of 5 dots (one per prayer) with a small "you & spouse" indicator
/// under each. Taps into the prayer-log detail screen.
class PrayerLogCard extends ConsumerWidget {
  const PrayerLogCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(prayerDaySummaryProvider);
    final view = ref.watch(prayerDayViewProvider);
    final offset = ref.watch(prayerLogDayOffsetProvider);

    final ownCount = summary.ownCount;
    final spouseCount = summary.spouseCount;

    // Only ever claims shared time when the check-ins really were close. A
    // couple ten hours apart matches on completion but never on the clock, and
    // the old copy called that "together".
    String summaryLine() {
      if (spouseCount == 0) {
        // "Your spouse hasn't logged yet" is a true statement that reads as a
        // false one when her day started twenty minutes ago. Say which it is.
        final progress = view == null
            ? ''
            : spouseDayProgressLabel(view: view, offset: offset);
        return progress.isEmpty
            ? "You're first. Your spouse hasn't logged yet."
            : "You're first — $progress.";
      }
      if (summary.sharedInTime) {
        final gap = summary.closestGap!;
        final closeness =
            gap.inMinutes < 15 ? 'together' : 'within an hour of you';
        return '${summary.matchedCount} prayed $closeness.';
      }
      if (summary.matchedCount > 0) {
        return '${summary.matchedCount} of 5 matched with your spouse.';
      }
      return '$spouseCount from your spouse.';
    }

    return LovCard(
      onTap: () => context.push('/home/prayer'),
      padding: const EdgeInsets.all(LovSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today\'s prayers',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Text(
                '$ownCount of 5',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final p in _prayers)
                _PrayerDot(
                  prayer: p,
                  ownDone: summary.own.contains(p),
                  spouseDone: summary.spouse.contains(p),
                ),
            ],
          ),
          const SizedBox(height: LovSpace.md),
          Row(
            children: [
              Icon(
                // Fills on completion parity — both having prayed the same
                // prayer, each within their own day. Reachable regardless of
                // how far apart they are, unlike a clock-proximity test.
                summary.matchedCount > 0
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: LovSpace.xs),
              Expanded(
                child: Text(
                  summaryLine(),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrayerDot extends StatelessWidget {
  const _PrayerDot({
    required this.prayer,
    required this.ownDone,
    required this.spouseDone,
  });

  final Prayer prayer;
  final bool ownDone;
  final bool spouseDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: LovMotion.standard,
              curve: LovMotion.enter,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: ownDone
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerLow,
                shape: BoxShape.circle,
                border: ownDone
                    ? null
                    : Border.all(
                        color: theme.colorScheme.outlineVariant,
                        width: 1,
                      ),
              ),
            ),
            if (ownDone)
              Icon(Icons.check_rounded,
                  size: 16, color: theme.colorScheme.onPrimary),
            if (spouseDone)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: LovSpace.xs),
        Text(
          _shortLabel(prayer),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  String _shortLabel(Prayer p) => switch (p) {
        Prayer.fajr => 'Fajr',
        Prayer.dhuhr => 'Dhuhr',
        Prayer.asr => 'Asr',
        Prayer.maghrib => 'Magh.',
        Prayer.isha => 'Isha',
      };
}

