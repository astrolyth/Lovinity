import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/theme.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/widgets/lov_kit.dart';
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

const _arabic = {
  Prayer.fajr: 'الفجر',
  Prayer.dhuhr: 'الظهر',
  Prayer.asr: 'العصر',
  Prayer.maghrib: 'المغرب',
  Prayer.isha: 'العشاء',
};

class PrayerLogScreen extends ConsumerWidget {
  const PrayerLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final offset = ref.watch(prayerLogDayOffsetProvider);
    final view = ref.watch(prayerDayViewProvider);
    final ownProfile = ref.watch(ownProfileProvider).asData?.value;
    final spouseProfile = ref.watch(spouseProfileProvider).asData?.value;
    final logsAsync = ref.watch(prayerLogsForDayProvider);
    final isWife = ref.watch(isWifeProvider);
    final ownCycleHistory =
        ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
    final spouseSchedule = ref.watch(spousePrayerTimesProvider);
    final ownTimes = ref.watch(ownPrayerTimesProvider);
    final next = ref.watch(nextPrayerProvider);
    final now = ref.watch(nowTickerProvider).asData?.value ?? DateTime.now();
    final spouseName = _first(spouseProfile?.displayName) ?? 'Your spouse';

    // The day anchor is unknown until the device timezone resolves. Showing a
    // skeleton beats rendering a day that might be wrong for a frame.
    if (view == null) {
      return const LovPage(
        title: 'Prayer log',
        slivers: [SliverToBoxAdapter(child: _LogSkeleton())],
      );
    }

    final loggable = isLoggableOffset(offset);
    final isExempt = isSelectedDateExemptForCurrentUser(
      isWife: isWife,
      ownCycleHistory: ownCycleHistory,
      selectedDate: view.ownDay,
    );

    return LovPage(
      title: 'Prayer log',
      slivers: [
        SliverToBoxAdapter(
          child: LovRise(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _WeekCard(ownId: ownProfile?.id, spouseName: spouseName),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: LovRise(
            delay: const Duration(milliseconds: 100),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: LovEyebrow(
                      '${offset == 0 ? 'Today' : 'Yesterday'} · '
                      '${DateFormat('EEEE d MMMM').format(view.ownDay)}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Earlier day',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        ref.read(prayerLogDayOffsetProvider.notifier).goBack(),
                    icon: Icon(Icons.chevron_left_rounded, color: p.muted),
                  ),
                  IconButton(
                    tooltip: 'Later day',
                    visualDensity: VisualDensity.compact,
                    onPressed: offset == 0
                        ? null
                        : () => ref
                              .read(prayerLogDayOffsetProvider.notifier)
                              .goForward(),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (view.zonesDiffer)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                [
                  spouseOffsetSentence(view),
                  spouseDayProgressLabel(view: view, offset: offset),
                ].where((s) => s.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: LovRise(
            delay: const Duration(milliseconds: 150),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: logsAsync.when(
                loading: () => const _LogSkeleton(),
                error: (_, _) => const LovSurface(
                  child: Text('Could not load the prayer log'),
                ),
                data: (logs) => LovSurface(
                  padding: EdgeInsets.zero,
                  clip: true,
                  child: Column(
                    children: [
                      for (final (i, pr) in Prayer.values.indexed) ...[
                        if (i > 0) Divider(height: 1, color: p.surface2),
                        _PrayerRow(
                          prayer: pr,
                          time: offset == 0
                              ? ownTimes
                                    ?.where((t) => t.prayer == pr)
                                    .firstOrNull
                                    ?.at
                              : null,
                          isNext: offset == 0 && next?.prayer == pr,
                          ownLog: _findLog(logs, ownProfile?.id, pr),
                          spouseLog: _findLog(logs, spouseProfile?.id, pr),
                          spouseName: spouseName,
                          isEditable: loggable && !isExempt,
                          ownExempt: isExempt,
                          spouseDue:
                              offset != 0 ||
                              isPrayerDueForSpouse(
                                prayer: pr,
                                schedule: spouseSchedule,
                                now: now,
                              ),
                          onOwnToggle: (status) => _toggleOwn(
                            context: context,
                            ref: ref,
                            prayer: pr,
                            date: view.ownDay,
                            newStatus: status,
                            spouseName: spouseName,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: LovRise(
            delay: const Duration(milliseconds: 250),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: LovSurface(
                radius: 20,
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isExempt
                          ? Icons.favorite_border_rounded
                          : Icons.info_outline_rounded,
                      size: 20,
                      color: p.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isExempt
                            ? 'Resting — your prayers are excused today 🤍. '
                                  'The week counts only the prayers that apply.'
                            : 'Cycle-aware scoring: on excused days, the week '
                                  'counts only the prayers that apply, so the '
                                  'score stays whole.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: p.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
    required BuildContext context,
    required WidgetRef ref,
    required Prayer prayer,
    required DateTime date,
    required PrayerStatus? newStatus,
    required String spouseName,
  }) async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;
    final repo = ref.read(prayerLogRepositoryProvider);
    // Distinct haptic per direction: heavier for a log, light for an unlog.
    unawaited(newStatus == null ? LovHaptics.light() : LovHaptics.medium());
    Future<void> unlog() => repo.unlogPrayer(
      coupleId: couple.id,
      userId: session.user.id,
      date: date,
      prayer: prayer,
    );
    try {
      if (newStatus == null) {
        await unlog();
      } else {
        await repo.logPrayer(
          coupleId: couple.id,
          userId: session.user.id,
          date: date,
          prayer: prayer,
          status: newStatus,
        );
        if (context.mounted) {
          showLovToast(
            context,
            '${prayer.displayName} logged. $spouseName will see it.',
            onUndo: () async {
              await unlog();
              ref.read(prayerLogRefreshTickProvider.notifier).state++;
            },
          );
        }
      }
    } catch (_) {
      if (context.mounted) {
        showLovToast(
          context,
          "Couldn't save that — check your connection",
          icon: Icons.error_outline_rounded,
        );
      }
    }
    ref.read(prayerLogRefreshTickProvider.notifier).state++;
  }
}

String? _first(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  return n.split(RegExp(r'\s+')).first;
}

/// This week as a grid: one cell per prayer per day, gold top half for you,
/// rose bottom half for your spouse.
class _WeekCard extends ConsumerWidget {
  const _WeekCard({required this.ownId, required this.spouseName});
  final String? ownId;
  final String spouseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final logs = ref.watch(prayerWeekLogsProvider).asData?.value ?? const [];
    final today = DateTime.now();
    final days = [
      for (var i = 6; i >= 0; i--)
        DateTime(today.year, today.month, today.day - i),
    ];
    bool did(bool mine, DateTime d, Prayer pr) => logs.any(
      (e) =>
          (mine ? e.userId == ownId : e.userId != ownId) &&
          e.prayer == pr &&
          e.status == PrayerStatus.prayed &&
          e.date.year == d.year &&
          e.date.month == d.month &&
          e.date.day == d.day,
    );
    var you = 0, her = 0, both = 0;
    for (final d in days) {
      for (final pr in Prayer.values) {
        final a = did(true, d, pr), b = did(false, d, pr);
        if (a) you++;
        if (b) her++;
        if (a && b) both++;
      }
    }
    Widget legend(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
      ],
    );

    return LovSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LovEyebrow('This week, together'),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        text: '$both',
                        children: [
                          TextSpan(
                            text: ' / ${days.length * 5}',
                            style: lovDisplay(
                              context,
                              size: 18,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ),
                      style: lovDisplay(context, size: 36),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  legend(p.accent, 'You · $you'),
                  const SizedBox(height: 4),
                  legend(p.partner, '$spouseName · $her'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const SizedBox(width: 52),
              for (final (i, d) in days.indexed)
                Expanded(
                  child: Text(
                    DateFormat.E().format(d).substring(0, 1),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: i == days.length - 1 ? p.text : p.muted,
                    ),
                  ),
                ),
            ],
          ),
          for (final pr in Prayer.values)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      pr.displayName,
                      style: TextStyle(fontSize: 12, color: p.muted),
                    ),
                  ),
                  for (final (i, d) in days.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _Cell(
                          you: did(true, d, pr),
                          her: did(false, d, pr),
                          today: i == days.length - 1,
                        ),
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

class _Cell extends StatelessWidget {
  const _Cell({required this.you, required this.her, required this.today});
  final bool you, her, today;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final cell = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 22,
        child: Column(
          children: [
            Expanded(child: ColoredBox(color: you ? p.accent : p.surface2)),
            const SizedBox(height: 2),
            Expanded(child: ColoredBox(color: her ? p.partner : p.surface2)),
          ],
        ),
      ),
    );
    if (!today) return cell;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.text, width: 1.5),
      ),
      child: cell,
    );
  }
}

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.prayer,
    required this.time,
    required this.isNext,
    required this.ownLog,
    required this.spouseLog,
    required this.isEditable,
    required this.onOwnToggle,
    required this.spouseName,
    required this.spouseDue,
    this.ownExempt = false,
  });

  final Prayer prayer;
  final DateTime? time;
  final bool isNext;
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
    final p = context.lov;
    final ownDone = ownLog?.status == PrayerStatus.prayed;
    final spouseDone = spouseLog?.status == PrayerStatus.prayed;
    final when = time == null
        ? null
        : DateFormat.jm().format(time!).toLowerCase();
    final sub = [
      ?when,
      if (isNext && !ownDone) 'next',
      _footerLabel(),
    ].join(' · ');

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Opacity(
              opacity: ownExempt ? .45 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        prayer.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _arabic[prayer]!,
                        style: lovArabic(
                          context,
                          size: 16,
                          color: p.muted,
                        ).copyWith(height: 1.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12, color: p.muted)),
                ],
              ),
            ),
          ),
          if (isNext && !ownDone && isEditable) ...[
            LovPressable(
              onTap: () => onOwnToggle(PrayerStatus.prayed),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Mark prayed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.onAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ] else ...[
            Semantics(
              button: isEditable,
              label: ownDone ? 'You prayed. Tap to undo' : 'You, not yet',
              excludeSemantics: true,
              child: LovPressable(
                onTap: isEditable
                    ? () => onOwnToggle(ownDone ? null : PrayerStatus.prayed)
                    : null,
                scale: .85,
                child: Padding(
                  // A 44pt target around the 26pt dot.
                  padding: const EdgeInsets.all(9),
                  child: _Dot(
                    on: ownDone,
                    color: p.accent,
                    onColor: p.onAccent,
                  ),
                ),
              ),
            ),
          ],
          Semantics(
            label: spouseDone ? '$spouseName prayed' : '$spouseName, not yet',
            excludeSemantics: true,
            child: _Dot(on: spouseDone, color: p.partner, onColor: p.onPartner),
          ),
        ],
      ),
    );
  }

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
      return gap == null ? 'both prayed' : 'both prayed · $gap';
    }
    if (ownDone) {
      return notDue.isEmpty ? "you've prayed" : "you've prayed · $notDue";
    }
    if (spouseDone) return '$spouseName prayed';
    return notDue.isEmpty ? 'not yet' : notDue;
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
}

/// Filled dot with a check when prayed, dashed ring when not.
class _Dot extends StatelessWidget {
  const _Dot({required this.on, required this.color, required this.onColor});
  final bool on;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: LovMotion.springOut,
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: on
          ? Container(
              key: const ValueKey(true),
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 16, color: onColor),
            )
          : SizedBox(
              key: const ValueKey(false),
              width: 26,
              height: 26,
              child: CustomPaint(painter: _DashedCircle(p.line2)),
            ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    final path = Path()..addOval((Offset.zero & size).deflate(.75));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 5) {
        canvas.drawPath(m.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

class _LogSkeleton extends StatelessWidget {
  const _LogSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          LovShimmerBox(height: 220, radius: 24),
          SizedBox(height: 24),
          LovShimmerBox(height: 320, radius: 24),
        ],
      ),
    );
  }
}
