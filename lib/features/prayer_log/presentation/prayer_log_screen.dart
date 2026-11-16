import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/prayer_log_providers.dart';
import '../../../shared/models/cycle_record.dart';
import '../../../shared/models/prayer_log.dart';

/// Whether the CURRENT USER's prayer tiles are excused for [selectedDate].
///
/// True only when she is the wife AND [selectedDate] falls within one of her
/// own cycle records (`CycleRecord.isActiveOn`). Pure/side-effect-free so it
/// can be unit-tested independently of the widget tree.
///
/// [selectedDate] must be the user's OWN resolved day. Exemption is a fact
/// about her body on her calendar; resolving it against a partner's day (or a
/// shared one) would excuse or un-excuse the wrong date near midnight.
bool isSelectedDateExemptForCurrentUser({
  required bool isWife,
  required List<CycleRecord> ownCycleHistory,
  required DateTime selectedDate,
}) {
  if (!isWife) return false;
  return ownCycleHistory.any((r) => r.isActiveOn(selectedDate));
}

class PrayerLogScreen extends ConsumerWidget {
  const PrayerLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final offset = ref.watch(prayerLogDayOffsetProvider);
    final summary = ref.watch(prayerDaySummaryProvider);
    final view = ref.watch(prayerDayViewProvider);
    final ownProfile = ref.watch(ownProfileProvider).asData?.value;
    final spouseProfile = ref.watch(spouseProfileProvider).asData?.value;
    final logsAsync = ref.watch(prayerLogsForDayProvider);
    final isWife = ref.watch(isWifeProvider);
    final ownCycleHistory =
        ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
    final spouseSchedule = ref.watch(spousePrayerTimesProvider);
    final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();

    // The day anchor is unknown until the device timezone resolves. Showing a
    // skeleton beats rendering a day that might be wrong for a frame.
    if (view == null) {
      return LovScaffold(
        title: 'Prayer log',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        child: const _LogSkeleton(),
      );
    }

    final loggable = isLoggableOffset(offset);
    final isExempt = isSelectedDateExemptForCurrentUser(
      isWife: isWife,
      ownCycleHistory: ownCycleHistory,
      selectedDate: view.ownDay,
    );
    final spouseName = spouseProfile?.displayName ?? 'Your spouse';

    return LovScaffold(
      title: 'Prayer log',
      subtitle: Text(
        offset == 0
            ? DateFormat('EEEE, d MMMM').format(view.ownDay)
            : DateFormat('EEEE, d MMM y').format(view.ownDay),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () =>
              ref.read(prayerLogDayOffsetProvider.notifier).goBack(),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: offset == 0
              ? null
              : () =>
                  ref.read(prayerLogDayOffsetProvider.notifier).goForward(),
        ),
      ],
      child: logsAsync.when(
        loading: () => const _LogSkeleton(),
        error: (e, _) => Center(
          child: Text('Could not load prayer log',
              style: theme.textTheme.bodyMedium),
        ),
        data: (logs) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DayToggle(
                offset: offset,
                onSelect: (o) =>
                    ref.read(prayerLogDayOffsetProvider.notifier).set(o),
              ),
              const SizedBox(height: LovSpace.lg),
              LovEnter(
                child: _TogetherStrip(
                  summary: summary,
                  view: view,
                  offset: offset,
                  ownName: ownProfile?.displayName ?? 'You',
                  spouseName: spouseName,
                ),
              ),
              if (isExempt) ...[
                const SizedBox(height: LovSpace.lg),
                const _ExemptionNote(),
              ],
              const SizedBox(height: LovSpace.xl),
              LovStagger(
                initialDelay: const Duration(milliseconds: 80),
                stagger: const Duration(milliseconds: 50),
                children: [
                  for (final p in Prayer.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LovSpace.md),
                      child: _PrayerRow(
                        prayer: p,
                        isEditable: loggable && !isExempt,
                        ownExempt: isExempt,
                        ownLog: _findLog(logs, ownProfile?.id, p),
                        spouseLog: _findLog(logs, spouseProfile?.id, p),
                        spouseName: spouseName,
                        // Only meaningful for the current day; a past day is
                        // entirely in the past for both of them.
                        spouseDue: offset != 0 ||
                            isPrayerDueForSpouse(
                              prayer: p,
                              schedule: spouseSchedule,
                              now: now,
                            ),
                        onOwnToggle: (newStatus) async {
                          await _toggleOwn(
                            ref: ref,
                            prayer: p,
                            date: view.ownDay,
                            newStatus: newStatus,
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: LovSpace.xxxl),
            ],
          ),
        ),
      ),
    );
  }

  PrayerLogEntry? _findLog(
    List<PrayerLogEntry> logs,
    String? userId,
    Prayer p,
  ) {
    if (userId == null) return null;
    for (final l in logs) {
      if (l.userId == userId && l.prayer == p) return l;
    }
    return null;
  }

  Future<void> _toggleOwn({
    required WidgetRef ref,
    required Prayer prayer,
    required DateTime date,
    required PrayerStatus? newStatus,
  }) async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;
    final repo = ref.read(prayerLogRepositoryProvider);
    // Distinct haptic per direction: heavier for a log, light for an unlog.
    if (newStatus == null) {
      unawaited(LovHaptics.light());
    } else {
      unawaited(LovHaptics.medium());
    }
    if (newStatus == null) {
      await repo.unlogPrayer(
        coupleId: couple.id,
        userId: session.user.id,
        date: date,
        prayer: prayer,
      );
    } else {
      await repo.logPrayer(
        coupleId: couple.id,
        userId: session.user.id,
        date: date,
        prayer: prayer,
        status: newStatus,
      );
    }
    ref.read(prayerLogRefreshTickProvider.notifier).state++;
  }
}

class _DayToggle extends StatelessWidget {
  const _DayToggle({required this.offset, required this.onSelect});

  final int offset;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _DayToggleButton(
            label: 'Today',
            selected: offset == 0,
            onTap: () => onSelect(0),
            theme: theme,
          ),
        ),
        const SizedBox(width: LovSpace.sm),
        Expanded(
          child: _DayToggleButton(
            label: 'Yesterday',
            selected: offset == 1,
            onTap: () => onSelect(1),
            theme: theme,
          ),
        ),
      ],
    );
  }
}

class _DayToggleButton extends StatelessWidget {
  const _DayToggleButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: LovMotion.standard,
        curve: LovMotion.enter,
        padding: const EdgeInsets.symmetric(vertical: LovSpace.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(LovRadius.md),
          border: selected
              ? null
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Counts for both spouses, and — when their zones disagree — the dual clock
/// that explains those counts.
///
/// The clock is adaptive rather than always-on: same-zone couples (the common
/// case) see exactly the layout they always have, and the extra chrome appears
/// only when there is a real discrepancy to account for. Without it, "0 of 5"
/// for a partner whose day started an hour ago reads as neglect instead of as
/// an early hour.
class _TogetherStrip extends StatelessWidget {
  const _TogetherStrip({
    required this.summary,
    required this.view,
    required this.offset,
    required this.ownName,
    required this.spouseName,
  });

  final PrayerDaySummary summary;
  final PrayerDayView view;
  final int offset;
  final String ownName;
  final String spouseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSec = theme.colorScheme.onSecondary;
    final dual = view.zonesDiffer;
    final progress = spouseDayProgressLabel(view: view, offset: offset);

    return Container(
      padding: const EdgeInsets.all(LovSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(LovRadius.lg),
      ),
      child: Column(
        children: [
          Row(
            // Centred rather than top-aligned with fixed padding: the dual
            // clock adds a line to each side, so any fixed offset would drift
            // out of alignment exactly when the layout expands.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _SideColumn(
                  name: ownName,
                  count: summary.ownCount,
                  clock: dual ? view.ownLocalTime : null,
                  day: dual ? view.ownDay : null,
                  alignEnd: false,
                ),
              ),
              Icon(
                summary.matchedCount > 0
                    ? Icons.favorite_rounded
                    : Icons.favorite_outline_rounded,
                color: onSec,
                size: 20,
              ),
              Expanded(
                child: _SideColumn(
                  name: spouseName,
                  count: summary.spouseCount,
                  clock: dual ? view.spouseLocalTime : null,
                  day: dual ? view.spouseDay : null,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (dual) ...[
            const SizedBox(height: LovSpace.md),
            Text(
              [spouseOffsetSentence(view), progress]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: onSec.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({
    required this.name,
    required this.count,
    required this.clock,
    required this.day,
    required this.alignEnd,
  });

  final String name;
  final int count;
  final DateTime? clock;
  final DateTime? day;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSec = theme.colorScheme.onSecondary;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: onSec.withValues(alpha: 0.7)),
        ),
        if (clock != null && day != null) ...[
          const SizedBox(height: 2),
          Text(
            '${DateFormat('EEE d MMM').format(day!)} · '
            '${DateFormat.jm().format(clock!)}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: onSec.withValues(alpha: 0.6)),
          ),
        ],
        const SizedBox(height: 2),
        LovDigitRow(
          value: count,
          minDigits: 1,
          style: theme.textTheme.displaySmall?.copyWith(
            color: onSec,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ExemptionNote extends StatelessWidget {
  const _ExemptionNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LovCard(
      variant: LovCardVariant.tonal,
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.lg,
        vertical: LovSpace.md,
      ),
      child: Text(
        'Resting — prayers are excused 🤍',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.prayer,
    required this.ownLog,
    required this.spouseLog,
    required this.isEditable,
    required this.onOwnToggle,
    required this.spouseName,
    required this.spouseDue,
    this.ownExempt = false,
  });

  final Prayer prayer;
  final PrayerLogEntry? ownLog;
  final PrayerLogEntry? spouseLog;
  final bool isEditable;
  final ValueChanged<PrayerStatus?> onOwnToggle;
  final String spouseName;

  /// Whether this prayer's time has arrived where the spouse is.
  final bool spouseDue;
  final bool ownExempt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ownDone = ownLog?.status == PrayerStatus.prayed;
    final spouseDone = spouseLog?.status == PrayerStatus.prayed;

    return LovCard(
      variant: LovCardVariant.plain,
      padding: const EdgeInsets.symmetric(
        horizontal: LovSpace.lg,
        vertical: LovSpace.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: ownExempt ? 0.4 : 1.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        prayer.displayName,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(width: LovSpace.sm),
                      Text(
                        _arabicName(prayer),
                        style: LovTypography.arabicText(
                          fontSize: 18,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _footerLabel(),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (spouseDone)
            Container(
              margin: const EdgeInsets.only(right: LovSpace.sm),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                shape: BoxShape.circle,
              ),
            ),
          Opacity(
            opacity: ownExempt ? 0.4 : 1.0,
            child: _CheckToggle(
              checked: ownDone,
              enabled: isEditable,
              onChanged: () =>
                  onOwnToggle(ownDone ? null : PrayerStatus.prayed),
            ),
          ),
        ],
      ),
    );
  }

  String _arabicName(Prayer p) => switch (p) {
        Prayer.fajr => 'ٱلْفَجْر',
        Prayer.dhuhr => 'ٱلظُّهْر',
        Prayer.asr => 'ٱلْعَصْر',
        Prayer.maghrib => 'ٱلْمَغْرِب',
        Prayer.isha => 'ٱلْعِشَاء',
      };

  /// States only what the data supports.
  ///
  /// The important case is the last one: when the spouse has not logged AND
  /// the prayer is not yet due where she is, a flat "Not yet" invites the
  /// reader to conclude she skipped it. She hasn't — it isn't time there.
  String _footerLabel() {
    final ownDone = ownLog?.status == PrayerStatus.prayed;
    final spouseDone = spouseLog?.status == PrayerStatus.prayed;
    final notDue = spouseDue ? '' : 'not due yet for $spouseName';

    if (ownDone && spouseDone) {
      final gap = _gapLabel();
      return gap == null ? 'Both prayed' : 'Both prayed · $gap';
    }
    if (ownDone) {
      return notDue.isEmpty ? "You've prayed" : "You've prayed · $notDue";
    }
    if (spouseDone) return '$spouseName prayed';
    return notDue.isEmpty ? 'Not yet' : _capitalise(notDue);
  }

  /// Real elapsed time between the two check-ins, shown only when it is small
  /// enough to describe as shared. Computed on `time_logged` instants, which
  /// are absolute — so this is one of the few quantities here that is already
  /// timezone-independent.
  String? _gapLabel() {
    final own = ownLog;
    final spouse = spouseLog;
    if (own == null || spouse == null) return null;
    final gap = syncGap(a: own.timeLogged, b: spouse.timeLogged);
    if (gap > kTogethernessWindow) return null;
    if (gap.inMinutes < 1) return 'within a minute';
    return '${gap.inMinutes}m apart';
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _CheckToggle extends StatefulWidget {
  const _CheckToggle({
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  final bool checked;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  State<_CheckToggle> createState() => _CheckToggleState();
}

class _CheckToggleState extends State<_CheckToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void didUpdateWidget(covariant _CheckToggle old) {
    super.didUpdateWidget(old);
    if (old.checked != widget.checked) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTapDown:
          widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel:
          widget.enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onChanged();
            }
          : null,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          // Spring-out overshoot: quickly to 1.18 then settle to 1.0.
          final bounce = t == 0
              ? 1.0
              : 1.0 +
                  0.18 *
                      (1 - t) *
                      (t < 0.4
                          ? (t / 0.4)
                          : 1 - ((t - 0.4) / 0.6) * 0.6);
          final pressScale = _pressed && widget.enabled ? 0.92 : 1.0;
          return Transform.scale(scale: bounce * pressScale, child: child);
        },
        child: AnimatedContainer(
          duration: LovMotion.standard,
          curve: LovMotion.enter,
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: widget.checked
                ? scheme.primary
                : scheme.surfaceContainerLow,
            shape: BoxShape.circle,
            border: widget.checked
                ? null
                : Border.all(color: scheme.outlineVariant, width: 1.5),
            boxShadow: widget.checked
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: LovMotion.standard,
            switchInCurve: LovMotion.springOut,
            switchOutCurve: LovMotion.enter,
            transitionBuilder: (c, a) => ScaleTransition(
              scale: Tween<double>(begin: 0.4, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: c),
            ),
            child: widget.checked
                ? Icon(
                    Icons.check_rounded,
                    key: const ValueKey('checked'),
                    size: 24,
                    color: scheme.onPrimary,
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
        ),
      ),
    );
  }
}

class _LogSkeleton extends StatelessWidget {
  const _LogSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: LovSpace.lg),
      child: Column(
        children: [
          LovShimmerBox(height: 88, radius: LovRadius.lg),
          SizedBox(height: LovSpace.lg),
          LovShimmerBox(height: 72, radius: LovRadius.lg),
          SizedBox(height: LovSpace.md),
          LovShimmerBox(height: 72, radius: LovRadius.lg),
          SizedBox(height: LovSpace.md),
          LovShimmerBox(height: 72, radius: LovRadius.lg),
          SizedBox(height: LovSpace.md),
          LovShimmerBox(height: 72, radius: LovRadius.lg),
          SizedBox(height: LovSpace.md),
          LovShimmerBox(height: 72, radius: LovRadius.lg),
        ],
      ),
    );
  }
}
