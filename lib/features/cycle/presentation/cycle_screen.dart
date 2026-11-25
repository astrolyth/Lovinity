import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/theme.dart';
import '../../../core/time/local_day.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../../shared/models/cycle_record.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../settings/domain/settings_providers.dart';
import '../data/cycle_repository.dart';
import '../domain/cycle_providers.dart';

class CycleScreen extends ConsumerWidget {
  const CycleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gate on the profile having resolved before branching on `isWifeProvider`
    // so a wife never flashes the husband's read-only view (or vice versa)
    // while `ownProfileProvider` is still loading. Same convention as
    // HomeScreen's `profileReady = own.hasValue`.
    final profileReady = ref.watch(ownProfileProvider).hasValue;
    final isWife = ref.watch(isWifeProvider);
    final history = isWife
        ? ref.watch(ownCycleHistoryProvider).asData?.value ?? const []
        : ref.watch(partnerSharedCycleProvider).asData?.value ?? const [];

    return LovPage(
      title: 'Cycle',
      action: LovIconButton(
        icon: Icons.history_rounded,
        label: 'Cycle history',
        onTap: () => _openHistory(context, history),
      ),
      slivers: [
        if (!profileReady)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else
          SliverToBoxAdapter(
            child: isWife ? const _WifeCycleView() : const _PartnerCycleView(),
          ),
      ],
    );
  }

  void _openHistory(BuildContext context, List<CycleRecord> history) {
    final df = DateFormat.MMMMd();
    showLovSheet<void>(
      context,
      title: 'History',
      subtitle: 'Only the two of you can see this.',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Nothing recorded yet.',
                style: TextStyle(color: sheet.lov.muted),
              ),
            ),
          for (final r in history)
            LovSheetRow(
              icon: Icons.water_drop_outlined,
              title: r.endedOn == null
                  ? '${df.format(r.startedOn)} — ongoing'
                  : '${df.format(r.startedOn)} – ${df.format(r.endedOn!)}',
            ),
          const SizedBox(height: 12),
          LovQuietButton(label: 'Close', onPressed: () => Navigator.pop(sheet)),
        ],
      ),
    );
  }
}

/// Day of the cycle (1-based) from the most recent start, if any.
int? _cycleDay(List<CycleRecord> history) {
  if (history.isEmpty) return null;
  final last = history
      .map((r) => r.startedOn)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final now = DateTime.now();
  final d = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(last.year, last.month, last.day)).inDays;
  return d < 0 ? null : d + 1;
}

/// A gentle, approximate phase label. Estimates only — never advice.
String _phase(int day, int cycle, int period) {
  if (day <= period) return 'Period';
  final ovulation = cycle - 14;
  if ((day - ovulation).abs() <= 1) return 'Likely ovulation';
  if (day >= ovulation - 5 && day <= ovulation + 1) return 'Fertile window';
  return day < ovulation ? 'Follicular phase' : 'Luteal phase';
}

/// The wife's own cycle tracking: start/end controls, prediction, history.
/// Only ever rendered when `isWifeProvider` is true -- the husband has no
/// path to `startCycle`/`endCycle` from this screen.
class _WifeCycleView extends ConsumerWidget {
  const _WifeCycleView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final active = ref.watch(activeCycleProvider);
    final history =
        ref.watch(ownCycleHistoryProvider).asData?.value ?? const [];
    final prediction = ref.watch(cyclePredictionProvider);
    final shareDefault = ref.watch(shareCycleByDefaultProvider);
    final spouse =
        ref.watch(spouseProfileProvider).asData?.value?.displayName.trim() ??
        '';
    final spouseName = spouse.isEmpty ? 'your spouse' : spouse.split(' ').first;
    final cycle = prediction.avgCycleLength ?? 28;
    final period = prediction.avgPeriodLength ?? 5;
    final day = _cycleDay(history);
    final moods = ref.watch(ownTodayMoodsProvider);
    void saveMoods(Set<String> next, bool shared) {
      final self = ref.read(authSessionProvider).asData?.value?.user.id;
      final coupleId = ref.read(currentCoupleProvider).asData?.value?.id;
      if (self == null || coupleId == null) return;
      ref
          .read(cycleRepositoryProvider)
          .setMoods(
            userId: self,
            coupleId: coupleId,
            day: ref.read(todayKeyProvider),
            moods: next,
            shared: shared,
          )
          .catchError((_) {
            if (context.mounted) {
              showLovToast(
                context,
                "Couldn't save your mood",
                icon: Icons.error_outline_rounded,
              );
            }
          });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LovRise(
          child: _Ring(
            day: day,
            cycle: cycle,
            period: period,
            label: active != null
                ? 'Resting 🤍'
                : day == null
                ? 'Not tracked yet'
                : _phase(day, cycle, period),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: active != null
              ? LovPrimaryButton(
                  label: 'End period',
                  onPressed: () => ref
                      .read(cycleRepositoryProvider)
                      .endCycle(recordId: active.id, endedOn: DateTime.now()),
                )
              : LovPrimaryButton(
                  label: 'Start period',
                  onPressed: () async {
                    final session = ref.read(authSessionProvider).asData?.value;
                    final couple = ref
                        .read(currentCoupleProvider)
                        .asData
                        ?.value;
                    if (session == null || couple == null) return;
                    await ref
                        .read(cycleRepositoryProvider)
                        .startCycle(
                          userId: session.user.id,
                          coupleId: couple.id,
                          startedOn: DateTime.now(),
                          visibility: shareDefault ? 'shared' : 'private',
                        );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Next period',
                  value: prediction.nextStart == null
                      ? '—'
                      : DateFormat('d MMM').format(prediction.nextStart!),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  label: 'Average cycle',
                  value: prediction.avgCycleLength == null
                      ? '—'
                      : '$cycle days',
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: LovSurface(
            radius: 20,
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: p.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'When your period starts, prayers are excused and your '
                    'score counts only the days that apply. This is a mercy — '
                    'take care of yourself.',
                    style: TextStyle(fontSize: 13, height: 1.5, color: p.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: LovEyebrow('How are you today?'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(key: k, value: label)
                  in cycleMoodLabels.entries)
                FilterChip(
                  label: Text(label),
                  selected: moods.contains(k),
                  showCheckmark: false,
                  onSelected: (on) {
                    HapticFeedback.selectionClick();
                    saveMoods(
                      on ? {...moods, k} : ({...moods}..remove(k)),
                      shareDefault,
                    );
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: LovSurface(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share with $spouseName',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shareDefault
                            ? 'They see your period days and mood, never your notes.'
                            : 'They only see that your score is resting.',
                        style: TextStyle(fontSize: 12, color: p.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: shareDefault,
                  onChanged: (v) async {
                    final session = ref.read(authSessionProvider).asData?.value;
                    if (session == null) return;
                    final current =
                        ref.read(preferencesProvider).asData?.value ?? const {};
                    await ref
                        .read(preferencesRepositoryProvider)
                        .setKey(
                          userId: session.user.id,
                          key: 'share_cycle_default',
                          value: v,
                          current: Map<String, dynamic>.from(current),
                        );
                    if (active != null) {
                      await ref
                          .read(cycleRepositoryProvider)
                          .setVisibility(
                            recordId: active.id,
                            visibility: v ? 'shared' : 'private',
                          );
                    }
                    // Today's mood follows the same choice.
                    if (moods.isNotEmpty) saveMoods(moods, v);
                    ref.invalidate(preferencesProvider);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The husband's read-only view of his wife's shared cycle records. No
/// start/end controls exist here -- there is nothing on this screen that
/// can write a `cycle_records` row for a non-wife account.
class _PartnerCycleView extends ConsumerWidget {
  const _PartnerCycleView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final active = ref.watch(partnerActiveCycleProvider);
    final history =
        ref.watch(partnerSharedCycleProvider).asData?.value ?? const [];
    final mood = ref.watch(partnerLatestMoodProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LovSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active != null ? "She's resting 🤍" : 'Cycle updates',
                  style: lovDisplay(context, size: 21),
                ),
                const SizedBox(height: 8),
                Text(
                  active != null
                      ? 'She is on her period right now, so her prayers are '
                            'excused. A little extra kindness and patience goes '
                            'a long way — take good care of her.'
                      : "She'll share an update here if she chooses to.",
                  style: TextStyle(fontSize: 14, height: 1.5, color: p.text2),
                ),
                if (mood != null) ...[
                  const SizedBox(height: 14),
                  LovEyebrow(
                    mood.day == dayKey(DateTime.now())
                        ? 'How she feels today'
                        : 'How she felt yesterday',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in mood.moods)
                        LovPill(label: cycleMoodLabels[m] ?? m),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
              child: Text(
                'Nothing shared yet.',
                style: TextStyle(fontSize: 13, color: p.muted),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            _Ring(
              day: _cycleDay(history),
              cycle: 28,
              period: 5,
              label: active != null ? 'Resting' : 'Shared with you',
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => LovSurface(
    radius: 20,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: context.lov.muted)),
        const SizedBox(height: 4),
        Text(value, style: lovDisplay(context, size: 22)),
      ],
    ),
  );
}

/// The cycle as a ring of days: period days in rose, the likely fertile
/// window dimmer, today ringed.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.day,
    required this.cycle,
    required this.period,
    required this.label,
  });
  final int? day;
  final int cycle;
  final int period;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    Widget key(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(fontSize: 12, color: p.muted)),
      ],
    );
    final fertile = Color.lerp(p.partner, p.bg, .55)!;
    return Semantics(
      label: day == null ? label : 'Day $day of $cycle, $label',
      excludeSemantics: true,
      child: Column(
        children: [
          const SizedBox(height: 12),
          SizedBox(
            width: 260,
            height: 260,
            child: CustomPaint(
              painter: _DaysPainter(
                day: day,
                cycle: cycle,
                period: period,
                track: p.surface2,
                periodColor: p.partner,
                fertile: fertile,
                today: p.text,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LovEyebrow('Today'),
                    Text(
                      day == null ? '—' : 'Day $day',
                      style: lovDisplay(context, size: 56, height: 1.05),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(fontSize: 14, color: p.partnerHi),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              key(p.partner, 'Period'),
              const SizedBox(width: 16),
              key(fertile, 'Fertile'),
              const SizedBox(width: 16),
              key(p.text, 'Today'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DaysPainter extends CustomPainter {
  _DaysPainter({
    required this.day,
    required this.cycle,
    required this.period,
    required this.track,
    required this.periodColor,
    required this.fertile,
    required this.today,
  });
  final int? day;
  final int cycle, period;
  final Color track, periodColor, fertile, today;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 14;
    final ovulation = cycle - 14;
    for (var d = 1; d <= cycle; d++) {
      final a = -math.pi / 2 + 2 * math.pi * (d - .5) / cycle;
      final pos = c + Offset(math.cos(a), math.sin(a)) * r;
      final color = d <= period
          ? periodColor
          : (d >= ovulation - 5 && d <= ovulation + 1)
          ? fertile
          : track;
      canvas.drawCircle(pos, 6, Paint()..color = color);
      if (d == day) {
        canvas.drawCircle(
          pos,
          10,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = today,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DaysPainter old) =>
      old.day != day || old.cycle != cycle || old.periodColor != periodColor;
}
