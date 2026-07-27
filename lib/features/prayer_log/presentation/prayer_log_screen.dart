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
    final selectedDate = ref.watch(prayerLogSelectedDateProvider);
    final summary = ref.watch(prayerDaySummaryProvider);
    final ownProfile = ref.watch(ownProfileProvider).asData?.value;
    final spouseProfile = ref.watch(spouseProfileProvider).asData?.value;
    final logsAsync = ref.watch(prayerLogsForDayProvider);
    final isWife = ref.watch(isWifeProvider);
    final ownCycleHistory =
        ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];

    final today = DateTime.now();
    final isToday = _sameDay(selectedDate, today);
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday = _sameDay(selectedDate, yesterday);
    final loggable = isLoggableDate(selectedDate);
    final isExempt = isSelectedDateExemptForCurrentUser(
      isWife: isWife,
      ownCycleHistory: ownCycleHistory,
      selectedDate: selectedDate,
    );

    return LovScaffold(
      title: 'Prayer log',
      subtitle: Text(
        isToday
            ? DateFormat('EEEE, d MMMM').format(selectedDate)
            : DateFormat('EEEE, d MMM y').format(selectedDate),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            ref.read(prayerLogSelectedDateProvider.notifier).set(
              selectedDate.subtract(const Duration(days: 1)),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isToday
              ? null
              : () {
                  ref.read(prayerLogSelectedDateProvider.notifier).set(
                    selectedDate.add(const Duration(days: 1)),
                  );
                },
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
                isToday: isToday,
                isYesterday: isYesterday,
                onSelect: (d) {
                  ref.read(prayerLogSelectedDateProvider.notifier).set(d);
                },
                today: today,
                yesterday: yesterday,
              ),
              const SizedBox(height: LovSpace.lg),
              LovEnter(
                child: _TogetherStrip(
                  ownCount: summary.ownCount,
                  spouseCount: summary.spouseCount,
                  togetherWindowSeconds: summary.togetherWindowSeconds,
                  ownName: ownProfile?.displayName ?? 'You',
                  spouseName: spouseProfile?.displayName ?? 'Your spouse',
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
                        onOwnToggle: (newStatus) async {
                          await _toggleOwn(
                            ref: ref,
                            prayer: p,
                            date: selectedDate,
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

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
  const _DayToggle({
    required this.isToday,
    required this.isYesterday,
    required this.onSelect,
    required this.today,
    required this.yesterday,
  });

  final bool isToday;
  final bool isYesterday;
  final ValueChanged<DateTime> onSelect;
  final DateTime today;
  final DateTime yesterday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _DayToggleButton(
            label: 'Today',
            selected: isToday,
            onTap: () => onSelect(today),
            theme: theme,
          ),
        ),
        const SizedBox(width: LovSpace.sm),
        Expanded(
          child: _DayToggleButton(
            label: 'Yesterday',
            selected: isYesterday,
            onTap: () => onSelect(yesterday),
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

class _TogetherStrip extends StatelessWidget {
  const _TogetherStrip({
    required this.ownCount,
    required this.spouseCount,
    required this.togetherWindowSeconds,
    required this.ownName,
    required this.spouseName,
  });

  final int ownCount;
  final int spouseCount;
  final int? togetherWindowSeconds;
  final String ownName;
  final String spouseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final togetherOK = togetherWindowSeconds != null;

    return Container(
      padding: const EdgeInsets.all(LovSpace.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary,
        borderRadius: BorderRadius.circular(LovRadius.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ownName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondary
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                LovDigitRow(
                  value: ownCount,
                  minDigits: 1,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            togetherOK ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
            color: theme.colorScheme.onSecondary,
            size: 20,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  spouseName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondary
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                LovDigitRow(
                  value: spouseCount,
                  minDigits: 1,
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    this.ownExempt = false,
  });

  final Prayer prayer;
  final PrayerLogEntry? ownLog;
  final PrayerLogEntry? spouseLog;
  final bool isEditable;
  final ValueChanged<PrayerStatus?> onOwnToggle;
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
                    _footerLabel(ownLog, spouseLog),
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

  String _footerLabel(PrayerLogEntry? own, PrayerLogEntry? spouse) {
    if (own == null && spouse == null) return 'Not yet';
    if (own?.status == PrayerStatus.prayed &&
        spouse?.status == PrayerStatus.prayed) {
      return 'Both prayed';
    }
    if (own?.status == PrayerStatus.prayed) return "You've prayed";
    if (spouse?.status == PrayerStatus.prayed) return 'Your spouse prayed';
    return 'Not yet';
  }
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
