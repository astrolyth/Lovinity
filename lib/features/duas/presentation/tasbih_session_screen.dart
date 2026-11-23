import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/tasbih_channel.dart';
import '../domain/tap_batcher.dart';
import '../domain/tasbih_providers.dart';

/// Waits for the session and couple ids before opening the channel/batcher,
/// which capture them (a realtime couple stream can briefly lose its value).
class TasbihSessionScreen extends ConsumerWidget {
  const TasbihSessionScreen({super.key, required this.counterId});
  final String counterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selfId = ref.watch(
      authSessionProvider.select((s) => s.value?.user.id),
    );
    final coupleId = ref.watch(
      currentCoupleProvider.select((c) => c.value?.id),
    );
    if (selfId != null && coupleId != null) {
      return _Session(counterId: counterId);
    }
    return LovPage(
      title: 'Tasbih together',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'Connecting…',
              style: TextStyle(fontSize: 14, color: context.lov.muted),
            ),
          ),
        ),
      ],
    );
  }
}

class _Session extends ConsumerStatefulWidget {
  const _Session({required this.counterId});
  final String counterId;

  @override
  ConsumerState<_Session> createState() => _SessionState();
}

class _SessionState extends ConsumerState<_Session>
    with WidgetsBindingObserver {
  late final TasbihChannel _channel;
  late final TapBatcher _batcher;
  late final int _p0;
  StreamSubscription<int>? _deltaSub;
  StreamSubscription<bool>? _hereSub;
  int? _db; // total at open
  int _mine = 0;
  int _spouse = 0;
  bool _here = false;
  bool _armed = false; // true once we saw the total below target this session
  bool _seen = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel = ref.read(tasbihChannelProvider(widget.counterId));
    _batcher = ref.read(tasbihBatcherProvider(widget.counterId));
    _p0 = _batcher.pending; // unsaved taps from an earlier session
    final repo = ref.read(tasbihRepositoryProvider);
    final self = ref.read(authSessionProvider).value?.user.id;
    _deltaSub = _channel.spouseDeltas.listen((d) {
      if (!mounted) return;
      setState(() => _spouse += d);
      _checkGoal();
    });
    _hereSub = _channel.spouseHere.listen((h) {
      if (mounted) setState(() => _here = h);
    });
    if (self != null) {
      // Fetched directly (not via the cached provider) so it is always fresh.
      repo.totals(widget.counterId, selfId: self).then((t) {
        if (!mounted) return;
        setState(() => _db = t.total);
        _checkGoal();
      }, onError: (_) {});
    }
  }

  DhikrCounter? get _counter {
    final list = ref.read(tasbihCountersProvider).asData?.value;
    if (list == null) return null;
    for (final c in list) {
      if (c.id == widget.counterId) return c;
    }
    return null;
  }

  int get _total => (_db ?? 0) + _p0 + _mine + _spouse;

  /// Fires once, only when the total crosses target during this session.
  void _checkGoal() {
    final c = _counter;
    if (c == null || _db == null || _fired) return;
    if (!_seen) {
      _seen = true;
      _armed =
          _db! + _p0 < c.target; // only a crossing during this session counts
    }
    if (_armed && _total >= c.target) {
      _fired = true;
      ref
          .read(notificationStoreProvider)
          .insertBestEffort(
            kind: 'tasbih',
            title: 'Goal reached: ${c.title}',
            body: 'Together you reached ${c.target}. Alhamdulillah.',
            route: '/home/tasbih',
          );
    }
  }

  void _onTap() {
    LovHaptics.selection();
    _batcher.tap();
    _channel.tap();
    setState(() => _mine++);
    _checkGoal();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _batcher.flushNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deltaSub?.cancel();
    _hereSub?.cancel();
    _batcher.flushNow(); // batcher outlives the screen and retries on failure
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    ref.watch(tasbihChannelProvider(widget.counterId)); // keep alive
    ref.listen(tasbihCountersProvider, (_, _) => _checkGoal());
    final c = ref
        .watch(tasbihCountersProvider)
        .asData
        ?.value
        .where((x) => x.id == widget.counterId)
        .firstOrNull;
    final fullName =
        ref.watch(spouseProfileProvider).asData?.value?.displayName.trim() ??
        '';
    final name = fullName.isEmpty
        ? 'Your partner'
        : fullName.split(RegExp(r'\s+')).first;
    final target = c?.target ?? 0;
    final progress = target == 0 ? 0.0 : (_total / target).clamp(0.0, 1.0);
    final spouseShare = target == 0 ? 0.0 : (_spouse / target).clamp(0.0, 1.0);

    Widget person(String initial, String label, String value, bool partner) =>
        Expanded(
          child: LovSurface(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                LovAvatar(initial: initial, size: 28, partner: partner),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$label ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: value,
                          style: TextStyle(color: p.muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                if (partner && _here) const _LiveDot(),
              ],
            ),
          ),
        );

    return LovPage(
      title: 'Tasbih together',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              const SizedBox(height: 16),
              LovEyebrow(_here ? '$name is here with you' : '$name is away'),
              if (c?.arabicText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    c!.arabicText!,
                    textAlign: TextAlign.center,
                    style: lovArabic(context, size: 34).copyWith(height: 1.6),
                  ),
                ),
              Text(c?.title ?? 'Tasbih', style: lovDisplay(context, size: 18)),
              const SizedBox(height: 4),
              Text(
                '$_total / $target',
                style: TextStyle(fontSize: 13, color: p.muted),
              ),
              Expanded(
                child: Center(
                  child: Semantics(
                    button: true,
                    label: 'Count. $_total of $target together',
                    child: LovPressable(
                      key: const Key('tasbih-tap'),
                      scale: .97,
                      onTap: _onTap,
                      child: Container(
                        width: 280,
                        height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.surface,
                          border: Border.all(color: p.line),
                          boxShadow: [
                            BoxShadow(
                              color: p.accent.withValues(alpha: .25),
                              blurRadius: 80,
                              spreadRadius: -30,
                              offset: const Offset(0, 30),
                            ),
                          ],
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: progress),
                          duration: const Duration(milliseconds: 350),
                          curve: const Cubic(.16, 1, .3, 1),
                          builder: (_, v, child) => CustomPaint(
                            painter: _Arcs(
                              outer: v,
                              inner: spouseShare,
                              track: p.line,
                              gold: p.accent,
                              rose: p.partner,
                            ),
                            child: child,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$_total',
                                style: lovDisplay(context, size: 76, height: 1)
                                    .copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'of $target · tap',
                                style: TextStyle(fontSize: 14, color: p.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Row(
                  children: [
                    person('Y', 'You', '+$_mine', false),
                    const SizedBox(width: 10),
                    person(name, name, '+$_spouse', true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Gold arc for the shared total, rose arc inside it for your spouse's taps.
class _Arcs extends CustomPainter {
  _Arcs({
    required this.outer,
    required this.inner,
    required this.track,
    required this.gold,
    required this.rose,
  });
  final double outer, inner;
  final Color track, gold, rose;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    void ring(double r, double v, Color color, double w) {
      final base = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = track.withValues(alpha: .6);
      canvas.drawCircle(c, r, base);
      if (v <= 0) return;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * v,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    ring(size.width / 2 - 16, outer, gold, 6);
    ring(size.width / 2 - 32, inner, rose, 4);
  }

  @override
  bool shouldRepaint(_Arcs old) =>
      old.outer != outer || old.inner != inner || old.gold != gold;
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
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
  Widget build(BuildContext context) => Semantics(
    label: 'Live',
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: 1 - .65 * math.sin(_c.value * math.pi),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: context.lov.partner,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}
