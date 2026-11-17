import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/tasbih_channel.dart';
import '../domain/tap_batcher.dart';
import '../domain/tasbih_providers.dart';

class TasbihSessionScreen extends ConsumerStatefulWidget {
  const TasbihSessionScreen({super.key, required this.counterId});
  final String counterId;

  @override
  ConsumerState<TasbihSessionScreen> createState() =>
      _TasbihSessionScreenState();
}

class _TasbihSessionScreenState extends ConsumerState<TasbihSessionScreen>
    with WidgetsBindingObserver {
  late final TasbihChannel _channel;
  late final TapBatcher _batcher;
  StreamSubscription<int>? _deltaSub;
  StreamSubscription<bool>? _hereSub;
  String? _selfId;
  String? _coupleId;
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
    // Cached: ref is unusable inside dispose(), where the last flush runs.
    final repo = ref.read(tasbihRepositoryProvider);
    ref.listenManual(authSessionProvider, (_, s) {
      _selfId = s.asData?.value?.user.id;
    }, fireImmediately: true);
    ref.listenManual(currentCoupleProvider, (_, c) {
      _coupleId = c.asData?.value?.id;
    }, fireImmediately: true);
    _batcher = TapBatcher(
      flushEvery: const Duration(seconds: 5),
      save: (n) {
        final self = _selfId, couple = _coupleId;
        if (self == null || couple == null) {
          return Future.error(StateError('not ready'));
        }
        return repo.addContribution(
          counterId: widget.counterId,
          coupleId: couple,
          userId: self,
          count: n,
        );
      },
    );
    _deltaSub = _channel.spouseDeltas.listen((d) {
      if (!mounted) return;
      setState(() => _spouse += d);
      _checkGoal();
    });
    _hereSub = _channel.spouseHere.listen((h) {
      if (mounted) setState(() => _here = h);
    });
    ref.read(counterTotalsProvider(widget.counterId).future).then((t) {
      if (!mounted) return;
      setState(() => _db = t.total);
      _checkGoal();
    }, onError: (_) {});
  }

  DhikrCounter? get _counter {
    final list = ref.read(tasbihCountersProvider).asData?.value;
    if (list == null) return null;
    for (final c in list) {
      if (c.id == widget.counterId) return c;
    }
    return null;
  }

  int get _total => (_db ?? 0) + _mine + _spouse;

  /// Fires once, only when the total crosses target during this session.
  void _checkGoal() {
    final c = _counter;
    if (c == null || _db == null || _fired) return;
    if (!_seen) {
      _seen = true;
      _armed = _db! < c.target; // only a crossing during this session counts
    }
    if (_armed && _total >= c.target) {
      _fired = true;
      ref.read(notificationStoreProvider).insertBestEffort(
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
    _batcher.flushNow();
    _batcher.dispose();
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(tasbihChannelProvider(widget.counterId)); // keep alive
    ref.listen(tasbihCountersProvider, (_, _) => _checkGoal());
    final c = ref.watch(tasbihCountersProvider).asData?.value
        .where((x) => x.id == widget.counterId)
        .firstOrNull;
    final name = ref.watch(spouseProfileProvider).asData?.value?.displayName ??
        'Your partner';
    final target = c?.target ?? 0;
    final progress = target == 0 ? 0.0 : (_total / target).clamp(0.0, 1.0);

    return LovScaffold(
      title: c?.title ?? 'Tasbih',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      child: Column(
        children: [
          const SizedBox(height: LovSpace.lg),
          if (c?.arabicText != null)
            Text(c!.arabicText!,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall),
          const SizedBox(height: LovSpace.lg),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: LovSpace.sm),
          Text('$_total / $target', style: theme.textTheme.titleMedium),
          const SizedBox(height: LovSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle,
                  size: 10,
                  color: _here ? Colors.green : theme.disabledColor),
              const SizedBox(width: LovSpace.sm),
              Text(_here ? '$name is here' : '$name is away',
                  style: theme.textTheme.bodySmall),
            ],
          ),
          Expanded(
            child: Center(
              child: Semantics(
                button: true,
                label: 'Count',
                child: GestureDetector(
                  key: const Key('tasbih-tap'),
                  onTap: _onTap,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary,
                    ),
                    alignment: Alignment.center,
                    child: Text('$_mine',
                        style: theme.textTheme.displayMedium?.copyWith(
                            color: theme.colorScheme.onPrimary)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
