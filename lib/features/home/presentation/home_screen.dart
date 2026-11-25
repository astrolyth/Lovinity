import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/notifications/notification_providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/time/hijri_dates.dart';
import '../../../core/time/prayer_engine.dart';
import '../../../core/time/tz_sync.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../calendar/domain/calendar_providers.dart';
import '../../chat/domain/chat_providers.dart';
import '../../cycle/domain/cycle_providers.dart';
import '../../daily/domain/daily_content_providers.dart';
import '../../daily/domain/question_providers.dart';
import '../../dates/domain/date_providers.dart';
import '../../duas/domain/adhkar_providers.dart';
import '../../duas/domain/dua_providers.dart';
import '../../gratitude/domain/gratitude_providers.dart';
import '../../learning/domain/learning_providers.dart';
import '../../letters/domain/letter_providers.dart';
import '../../location/data/location_service.dart';
import '../../location/domain/location_providers.dart';
import '../../lovemap/domain/lovemap_providers.dart';
import '../../moments/domain/moments_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../../planning/domain/planning_providers.dart';
import '../../prayer_log/domain/adhan_reminders.dart';
import '../../prayer_log/domain/prayer_log_providers.dart';
import '../../scoring/domain/scoreboard_providers.dart';
import '../../wall/domain/wall_providers.dart';
import '../../widget/domain/widget_providers.dart';
import '../domain/home_providers.dart';

const _arabicPrayer = {
  Prayer.fajr: 'الفجر',
  Prayer.dhuhr: 'الظهر',
  Prayer.asr: 'العصر',
  Prayer.maghrib: 'المغرب',
  Prayer.isha: 'العشاء',
};

/// Home tiles are grouped Deen / Us / Home behind one switcher.
enum HomeGroup { deen, us, home }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeGroup _group = HomeGroup.deen;
  int _dir = 1; // tiles enter from the side the thumb moved toward

  void _select(HomeGroup g) => setState(() {
    _dir = g.index > _group.index ? 1 : -1;
    _group = g;
  });

  @override
  Widget build(BuildContext context) {
    // Session-wide pumps: Home is the always-present authed screen, so it
    // owns the subscriptions that keep badges, the OS widget and the
    // spouse-facing timezone current even when their feature isn't open.
    ref.watch(inboxPumpProvider);
    ref.watch(receiptPumpProvider);
    ref.watch(pairingNotificationPumpProvider);
    ref.watch(prayerNotificationPumpProvider);
    ref.watch(adhanReminderSchedulerProvider);
    ref.watch(cycleNotificationPumpProvider);
    ref.watch(questionNotificationPumpProvider);
    ref.watch(duaNotificationPumpProvider);
    ref.watch(adhkarNotificationPumpProvider);
    // Session-lifetime day rollover (resume + local midnight) for duas/adhkar.
    ref.listen(dayTickProvider, (_, _) {});
    ref.watch(gratitudeNotificationPumpProvider);
    ref.watch(calendarNotificationPumpProvider);
    ref.watch(groceryNotificationPumpProvider);
    ref.watch(letterNotificationPumpProvider);
    ref.watch(learningNotificationPumpProvider);
    ref.watch(loveMapNotificationPumpProvider);
    ref.watch(dateNotificationPumpProvider);
    ref.watch(widgetPublisherProvider);
    ref.watch(timezonePublishProvider);

    ref.listen(locationControllerProvider, (prev, next) {
      final err = next.error;
      if (next.hasError && err is LocationFailure) {
        showLovToast(context, err.userMessage, icon: Icons.location_off);
      }
    });

    final p = context.lov;
    final own = ref.watch(ownProfileProvider).asData?.value;
    final spouse = ref.watch(spouseProfileProvider).asData?.value;
    final spouseName = _firstName(spouse?.displayName) ?? 'your spouse';
    final unread =
        ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    final now = DateTime.now();
    final top = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            const Positioned.fill(child: LovAmbient()),
            CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, top + 14, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Icon(
                          Icons.dark_mode_outlined,
                          size: 20,
                          color: p.accent,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          // One line on narrow phones: shrink, never wrap.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              formatHijri(hijriFromGregorian(now)),
                              maxLines: 1,
                              style: TextStyle(fontSize: 13, color: p.muted),
                            ),
                          ),
                        ),
                        LovIconButton(
                          icon: Icons.notifications_none_rounded,
                          label: unread > 0
                              ? 'Notifications, $unread new'
                              : 'Notifications',
                          dot: unread > 0,
                          onTap: () => context.push('/home/notifications'),
                        ),
                        const SizedBox(width: 10),
                        LovIconButton(
                          icon: Icons.settings_outlined,
                          label: 'Settings and themes',
                          onTap: () => context.push('/home/settings'),
                        ),
                        const SizedBox(width: 10),
                        Semantics(
                          button: true,
                          label: 'You and $spouseName',
                          excludeSemantics: true,
                          child: LovPressable(
                            onTap: () => context.push('/home/us'),
                            child: LovDuo(
                              self: own?.displayName ?? '',
                              partner: spouse?.displayName ?? '',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: LovRise(
                    delay: const Duration(milliseconds: 50),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                      child: _Greeting(now: now, spouseName: spouseName),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: LovRise(
                    delay: Duration(milliseconds: 150),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _PrayerHero(),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: LovRise(
                    delay: const Duration(milliseconds: 250),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: LovSegmented<HomeGroup>(
                        values: HomeGroup.values,
                        labelOf: (g) => switch (g) {
                          HomeGroup.deen => 'Deen',
                          HomeGroup.us => 'Us',
                          HomeGroup.home => 'Home',
                        },
                        selected: _group,
                        onChanged: _select,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _TileGrid(
                      key: ValueKey(_group),
                      tiles: _tiles(context, ref, _group, own?.gender),
                      dir: _dir,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: LovRise(
                    delay: Duration(milliseconds: 500),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: _VerseCard(),
                    ),
                  ),
                ),
                // Clears the floating tab bar.
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String? _firstName(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  return n.split(RegExp(r'\s+')).first;
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.now, required this.spouseName});
  final DateTime now;
  final String spouseName;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final style = lovDisplay(context, size: 32, height: 1.08);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LovEyebrow('${DateFormat.EEEE().format(now)} · Assalamu alaikum'),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: style,
            children: [
              const TextSpan(text: 'You and '),
              TextSpan(
                text: spouseName,
                style: TextStyle(color: p.partner),
              ),
              const TextSpan(text: ','),
            ],
          ),
        ),
        LovShineText('together.', style: style),
      ],
    );
  }
}

// ---------------------------------------------------------------- hero

class _PrayerHero extends ConsumerStatefulWidget {
  const _PrayerHero();

  @override
  ConsumerState<_PrayerHero> createState() => _PrayerHeroState();
}

class _PrayerHeroState extends ConsumerState<_PrayerHero> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // The countdown is the only per-second thing on Home; keep it local.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final profile = ref.watch(ownProfileProvider);
    final hasLocation =
        profile.asData?.value?.latitude != null &&
        profile.asData?.value?.longitude != null;
    final next = ref.watch(nextPrayerProvider);
    final prev = ref.watch(previousPrayerProvider);
    final summary = ref.watch(prayerDaySummaryProvider);
    final spouseName =
        _firstName(
          ref.watch(spouseProfileProvider).asData?.value?.displayName,
        ) ??
        'Spouse';
    final board = ref.watch(scoreboardProvider).asData?.value;
    final streak = board == null
        ? 0
        : math.min(board.own.currentStreak, board.spouse.currentStreak);

    final now = DateTime.now();
    final left = next == null ? Duration.zero : next.at.difference(now);
    final span = (next != null && prev != null)
        ? next.at.difference(prev.at).inSeconds
        : 0;
    final elapsed = span <= 0
        ? 0.0
        : (1 - left.inSeconds / span).clamp(0.0, 1.0).toDouble();

    return LovBeam(
      radius: 28,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: p.hi.withValues(alpha: .08)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF28C3C).withValues(alpha: .45),
              blurRadius: 60,
              spreadRadius: -34,
              offset: const Offset(0, 34),
            ),
            BoxShadow(
              color: p.shadow.withValues(alpha: p.isDark ? .9 : .2),
              blurRadius: 40,
              spreadRadius: -20,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Stack(
            children: [
              Positioned.fill(child: _Dusk(sunDrop: elapsed * 70)),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!hasLocation)
                      _NoLocation(
                        busy: ref.watch(locationControllerProvider).isLoading,
                        onSet: () => ref
                            .read(locationControllerProvider.notifier)
                            .captureAndSave(),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _NextPrayer(next: next, left: left),
                          ),
                          const SizedBox(width: 16),
                          _Ring(
                            progress: elapsed,
                            label: next == null
                                ? ''
                                : _arabicPrayer[next.prayer]!,
                          ),
                        ],
                      ),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.fromLTRB(0, 18, 0, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            p.hi.withValues(alpha: 0),
                            p.hi.withValues(alpha: .12),
                            p.hi.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Prayed together today',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _Legend(color: p.accent, label: 'You'),
                        const SizedBox(width: 10),
                        _Legend(color: p.partner, label: spouseName),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final (i, pr) in Prayer.values.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _Pip(
                              label: pr.displayName,
                              you: summary.own.contains(pr),
                              her: summary.spouse.contains(pr),
                              isNext: next?.prayer == pr,
                              delay: Duration(milliseconds: 600 + 200 * i),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (streak > 0)
                          LovPill(
                            icon: Icons.local_fire_department_outlined,
                            label: streak == 1
                                ? '1 day together'
                                : '$streak days together',
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.push('/home/prayer'),
                          style: TextButton.styleFrom(
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Prayer log'),
                              SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded, size: 16),
                            ],
                          ),
                        ),
                      ],
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

class _NextPrayer extends StatelessWidget {
  const _NextPrayer({required this.next, required this.left});
  final ScheduledPrayer? next;
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final n = next;
    if (n == null) {
      return const LovEyebrow('Prayer times loading');
    }
    final secs = math.max(0, left.inSeconds);
    final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    final countdown = '$h:${two(m)}:${two(s)}';
    final time = DateFormat.jm().format(n.at).toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LovEyebrow('Next prayer'),
        const SizedBox(height: 6),
        Text(
          n.prayer.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: lovDisplay(context, size: 40, height: 1.05),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$time · in', style: TextStyle(fontSize: 13, color: p.muted)),
            const SizedBox(width: 8),
            Semantics(
              label: 'in $countdown',
              liveRegion: false,
              excludeSemantics: true,
              child: _Odometer(text: countdown),
            ),
          ],
        ),
      ],
    );
  }
}

/// Rolling digits (Magic UI number ticker): each digit slides to its value.
class _Odometer extends StatelessWidget {
  const _Odometer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = lovDisplay(
      context,
      size: 22,
      color: context.lov.accent,
      height: 1.2,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    const h = 22 * 1.2;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
        stops: [0, .18, .82, 1],
      ).createShader(r),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in text.characters)
            if (c == ':')
              SizedBox(
                width: 22 * .28,
                height: h,
                child: Center(child: Text(':', style: style)),
              )
            else
              SizedBox(
                width: 22 * .62,
                height: h,
                child: ClipRect(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: int.parse(c).toDouble()),
                    duration: context.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 750),
                    curve: lovBounce,
                    builder: (_, v, child) => OverflowBox(
                      alignment: Alignment.topCenter,
                      maxHeight: h * 10,
                      child: Transform.translate(
                        offset: Offset(0, -v * h),
                        child: child,
                      ),
                    ),
                    child: Column(
                      children: [
                        for (var d = 0; d < 10; d++)
                          SizedBox(
                            height: h,
                            child: Center(child: Text('$d', style: style)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.label});
  final double progress;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return SizedBox(
      width: 100,
      height: 100,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: context.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 1400),
        curve: const Cubic(.16, 1, .3, 1),
        builder: (_, v, child) => CustomPaint(
          painter: _RingPainter(v, p.line, p.accent),
          child: child,
        ),
        child: Center(child: Text(label, style: lovArabic(context, size: 22))),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.track, this.color);
  final double v;
  final Color track, color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = 42.0;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = track;
    canvas.drawCircle(c, r, base);
    if (v <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: .55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, glow);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.v != v || old.color != color || old.track != track;
}

/// Sunset light behind the hero; the sun sinks as the next prayer nears.
class _Dusk extends StatefulWidget {
  const _Dusk({required this.sunDrop});
  final double sunDrop;

  @override
  State<_Dusk> createState() => _DuskState();
}

class _DuskState extends State<_Dusk> with SingleTickerProviderStateMixin {
  late final _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _twinkle.stop() : _twinkle.repeat();
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    const stars = [
      (.24, .14, 0.0),
      (.48, .08, .3),
      (.62, .22, .52),
      (.12, .40, .15),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.cardA, p.cardB],
                stops: const [0, .75],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(.76, 1.16),
                radius: .9,
                colors: [
                  const Color(0xFFEE8C46).withValues(alpha: .36),
                  const Color(0xFFEE8C46).withValues(alpha: 0),
                ],
                stops: const [0, .62],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(.4, 1),
                radius: .6,
                colors: [
                  p.partner.withValues(alpha: .2),
                  p.partner.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 1200),
          curve: lovSpring,
          right: -6,
          top: -10 + widget.sunDrop,
          width: 150,
          height: 150,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0x80FFCD82),
                  Color(0x24F28C3C),
                  Color(0x00F28C3C),
                ],
                stops: [0, .52, .7],
              ),
            ),
          ),
        ),
        for (final (x, y, phase) in stars)
          Positioned.fill(
            child: Align(
              alignment: Alignment(x * 2 - 1, y * 2 - 1),
              child: AnimatedBuilder(
                animation: _twinkle,
                builder: (_, _) {
                  final t = (_twinkle.value + phase) % 1;
                  final o = .5 - .4 * math.sin(t * math.pi);
                  return Container(
                    width: 2,
                    height: 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.accentInk.withValues(alpha: o),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _NoLocation extends StatelessWidget {
  const _NoLocation({required this.busy, required this.onSet});
  final bool busy;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LovEyebrow('Next prayer'),
        const SizedBox(height: 6),
        Text('Set your location', style: lovDisplay(context, size: 28)),
        const SizedBox(height: 6),
        Text(
          'Prayer times are worked out on this phone from where you are.',
          style: TextStyle(fontSize: 13, color: p.muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        LovPrimaryButton(
          label: 'Use my location',
          icon: Icons.my_location_rounded,
          loading: busy,
          height: 46,
          expand: false,
          onPressed: busy ? null : onSet,
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: context.lov.muted)),
    ],
  );
}

/// One prayer: your half fills gold from the left, your spouse's rose from
/// the right; the next prayer breathes with a dashed outline.
class _Pip extends StatelessWidget {
  const _Pip({
    required this.label,
    required this.you,
    required this.her,
    required this.isNext,
    required this.delay,
  });
  final String label;
  final bool you;
  final bool her;
  final bool isNext;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    Widget half(bool on, Color c, Alignment from) => Expanded(
      child: _Fill(on: on, color: c, from: from, delay: delay),
    );
    return Semantics(
      label:
          '$label: ${you ? 'you prayed' : 'you not yet'}, '
          '${her ? 'spouse prayed' : 'spouse not yet'}',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: 28,
            child: isNext
                ? _Breathing(color: p.accent)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: ColoredBox(
                      color: p.surface2,
                      child: Row(
                        children: [
                          half(you, p.accent, Alignment.centerLeft),
                          const SizedBox(width: 2),
                          half(her, p.partner, Alignment.centerRight),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              color: isNext ? p.accent : p.muted,
              fontWeight: isNext ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({
    required this.on,
    required this.color,
    required this.from,
    required this.delay,
  });
  final bool on;
  final Color color;
  final Alignment from;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (!on) return const SizedBox.expand();
    return LovRise(
      delay: delay,
      offset: Offset.zero,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: context.reduceMotion ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: const Cubic(.16, 1, .3, 1),
        builder: (_, v, _) => FractionallySizedBox(
          alignment: from,
          widthFactor: v,
          heightFactor: 1,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}

class _Breathing extends StatefulWidget {
  const _Breathing({required this.color});
  final Color color;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    !context.allowLoops ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Opacity(
      opacity: 1 - .55 * math.sin(_c.value * math.pi),
      child: CustomPaint(
        painter: _DashedPill(widget.color),
        size: const Size.fromHeight(28),
      ),
    ),
  );
}

class _DashedPill extends CustomPainter {
  _DashedPill(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(.75),
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final metric in (Path()..addRRect(rr)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill old) => old.color != color;
}

// ---------------------------------------------------------------- tiles

class _TileSpec {
  const _TileSpec(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.subtitleColor,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? subtitleColor;
}

List<_TileSpec> _tiles(
  BuildContext context,
  WidgetRef ref,
  HomeGroup g,
  String? gender,
) {
  final p = context.lov;
  void push(String r) => context.push(r);
  switch (g) {
    case HomeGroup.deen:
      final done = ref.watch(prayerDaySummaryProvider).own.length;
      return [
        _TileSpec(
          Icons.dark_mode_outlined,
          'Prayer log',
          '$done of 5 today',
          () => push('/home/prayer'),
        ),
        _TileSpec(
          Icons.menu_book_outlined,
          'Duas',
          'Adhkar daily',
          () => push('/home/duas'),
        ),
        _TileSpec(
          Icons.blur_circular_rounded,
          'Tasbih',
          'Together',
          () => push('/home/tasbih'),
        ),
        _TileSpec(
          Icons.auto_stories_outlined,
          'Verse',
          ref.watch(dailyContentProvider).asData?.value?.verse?.reference ??
              'Today\'s ayah',
          () => push('/home/today'),
        ),
        _TileSpec(
          Icons.forum_outlined,
          'Question',
          'Both answer',
          () => push('/home/today'),
        ),
        _TileSpec(
          Icons.school_outlined,
          'Learn',
          'Lessons',
          () => push('/home/learn'),
        ),
      ];
    case HomeGroup.us:
      final unread = ref.watch(unreadChatCountProvider).asData?.value ?? 0;
      final self = ref.watch(wallSelfIdProvider);
      final momentsIn =
          ref
              .watch(momentsProvider)
              .asData
              ?.value
              .any((m) => m.senderId != self && m.viewedAt == null) ??
          false;
      return [
        _TileSpec(
          Icons.chat_bubble_outline_rounded,
          'Chat',
          unread > 0 ? '$unread unread' : 'Encrypted',
          () => push('/home/chat'),
          subtitleColor: unread > 0 ? p.partner : null,
        ),
        _TileSpec(
          Icons.photo_camera_outlined,
          'Moments',
          momentsIn ? 'Theirs is in' : 'Share now',
          () => context.go('/moments'),
          subtitleColor: momentsIn ? p.partner : null,
        ),
        _TileSpec(
          Icons.dashboard_outlined,
          'Wall',
          'Saved finds',
          () => context.go('/wall'),
        ),
        _TileSpec(
          Icons.mail_outline_rounded,
          'Letters',
          'Sealed notes',
          () => push('/home/letters'),
        ),
        _TileSpec(
          Icons.place_outlined,
          'Love map',
          'Get to know',
          () => push('/home/us'),
        ),
        _TileSpec(
          Icons.favorite_border_rounded,
          'Dates',
          'Ideas for two',
          () => push('/home/us'),
        ),
      ];
    case HomeGroup.home:
      return [
        _TileSpec(
          Icons.calendar_today_outlined,
          'Calendar',
          'Shared',
          () => push('/home/week'),
        ),
        _TileSpec(
          Icons.restaurant_outlined,
          'Meals',
          'Week plan',
          () => push('/home/week'),
        ),
        _TileSpec(
          Icons.format_list_bulleted_rounded,
          'Groceries',
          'One list',
          () => push('/home/week'),
        ),
        _TileSpec(
          Icons.wb_sunny_outlined,
          'Gratitude',
          "Write today's",
          () => push('/home/today'),
        ),
        if (gender == 'female')
          _TileSpec(
            Icons.water_drop_outlined,
            'Cycle',
            'Private',
            () => push('/home/cycle'),
          ),
        _TileSpec(
          Icons.volunteer_activism_outlined,
          'Care',
          'Gentle tips',
          () => push('/home/us'),
        ),
      ];
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({super.key, required this.tiles, required this.dir});
  final List<_TileSpec> tiles;
  final int dir;

  @override
  Widget build(BuildContext context) {
    final tint = switch (key) {
      ValueKey(value: HomeGroup.us) => context.lov.partner,
      ValueKey(value: HomeGroup.home) => const Color(0xFFA9D3B0),
      _ => null,
    };
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      mainAxisExtent: 108,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final (i, t) in tiles.indexed)
          LovRise(
            delay: Duration(milliseconds: 30 * i),
            offset: Offset(28.0 * dir, 0),
            child: LovTile(
              icon: t.icon,
              title: t.title,
              subtitle: t.subtitle,
              subtitleColor: t.subtitleColor,
              tint: tint,
              onTap: t.onTap,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- verse

class _VerseCard extends ConsumerWidget {
  const _VerseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.lov;
    final verse = ref.watch(dailyContentProvider).asData?.value?.verse;
    return LovSurface(
      onTap: () => context.push('/home/today'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LovEyebrow('Verse of the day'),
          if (verse == null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'Today\'s ayah will appear here.',
                style: TextStyle(fontSize: 15, color: p.muted),
              ),
            )
          else ...[
            const SizedBox(height: 14),
            Text(
              verse.arabicText,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: lovArabic(context, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              '"${verse.translation}"',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              verse.reference,
              style: TextStyle(fontSize: 12, color: p.muted),
            ),
          ],
        ],
      ),
    );
  }
}
