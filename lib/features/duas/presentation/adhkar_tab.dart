import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../../../core/widgets/lov_kit.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/adhkar_repository.dart';
import '../data/dua_library_repository.dart';
import '../domain/adhkar_providers.dart';
import '../domain/dua_library_providers.dart';
import 'library_tab.dart' show LibraryRetry;

/// Morning / evening / after-salah adhkar: pick a set, tap a row to count it.
/// Lays out as a column so it can sit inside the Duas page's scroll.
class AdhkarTab extends ConsumerStatefulWidget {
  const AdhkarTab({super.key});

  @override
  ConsumerState<AdhkarTab> createState() => _AdhkarTabState();
}

class _AdhkarTabState extends ConsumerState<AdhkarTab> {
  late AdhkarSet _set = DateTime.now().hour < 12
      ? AdhkarSet.morning
      : AdhkarSet.evening;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final dayKey = ref.watch(adhkarTodayKeyProvider);
    final profile = ref.watch(ownProfileProvider);
    Widget note(String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(t, style: TextStyle(fontSize: 14, color: p.muted)),
      ),
    );
    if (dayKey == null) {
      return profile.isLoading
          ? const Center(child: CircularProgressIndicator())
          : note('Adhkar are on their way.');
    }
    return ref
        .watch(duaLibraryProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const LibraryRetry(),
          data: (all) {
            final bySet = {
              for (final s in AdhkarSet.values)
                s: all.where((d) => d.category == s.dbValue).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
            };
            final sets = [
              for (final s in AdhkarSet.values)
                if (bySet[s]!.isNotEmpty) s,
            ];
            if (sets.isEmpty) return note('Adhkar are on their way.');
            final selected = sets.contains(_set) ? _set : sets.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LovSegmented<AdhkarSet>(
                  values: sets,
                  labelOf: (s) => s.label,
                  selected: selected,
                  height: 44,
                  onChanged: (s) => setState(() => _set = s),
                ),
                const SizedBox(height: 12),
                // Keyed on the day so a rollover reloads progress.
                _SetCard(
                  key: ValueKey('$dayKey|${selected.dbValue}'),
                  set: selected,
                  dayKey: dayKey,
                  items: bySet[selected]!,
                ),
              ],
            );
          },
        );
  }
}

class _SetCard extends ConsumerStatefulWidget {
  const _SetCard({
    super.key,
    required this.set,
    required this.dayKey,
    required this.items,
  });

  final AdhkarSet set;
  final String dayKey;
  final List<LibraryDua> items;

  @override
  ConsumerState<_SetCard> createState() => _SetCardState();
}

class _SetCardState extends ConsumerState<_SetCard> {
  Map<String, int>? _counts;
  bool _completeCalled = false;

  @override
  void initState() {
    super.initState();
    ref.read(adhkarProgressStoreProvider).load(widget.dayKey, widget.set).then((
      c,
    ) {
      if (mounted) setState(() => _counts = c);
    });
  }

  bool get _allDone =>
      widget.items.every((d) => (_counts![d.id] ?? 0) >= d.repeatCount);

  void _tap(LibraryDua d) {
    final n = _counts![d.id] ?? 0;
    if (n >= d.repeatCount) return;
    setState(() => _counts = {..._counts!, d.id: n + 1});
    // Best effort: a secure-storage failure only loses local progress.
    ref
        .read(adhkarProgressStoreProvider)
        .save(widget.dayKey, widget.set, _counts!)
        .catchError((_) {});
  }

  Future<void> _complete(String coupleId, String userId) async {
    try {
      await ref
          .read(adhkarRepositoryProvider)
          .complete(
            coupleId: coupleId,
            userId: userId,
            localDate: widget.dayKey,
            set: widget.set,
          );
    } catch (_) {
      // Progress stays local; the next app open retries (idempotent).
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final counts = _counts;
    final selfId = ref.watch(
      authSessionProvider.select((s) => s.asData?.value?.user.id),
    );
    final coupleId = ref.watch(
      currentCoupleProvider.select((c) => c.asData?.value?.id),
    );
    final completions = ref.watch(adhkarCompletionsProvider).asData?.value;
    final today = (completions ?? const <AdhkarCompletion>[]).where(
      (c) => c.localDate == widget.dayKey && c.set == widget.set,
    );
    final mine = today.any((c) => c.userId == selfId);
    final spouseDone = today.any((c) => c.userId != selfId);
    final done = counts != null && _allDone;
    if (done &&
        !mine &&
        !_completeCalled &&
        completions != null &&
        selfId != null &&
        coupleId != null) {
      _completeCalled = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _complete(coupleId, selfId),
      );
    }
    final spouseName =
        ref
            .watch(spouseProfileProvider.select((p) => p.asData?.value))
            ?.displayName ??
        '';
    final spouse = spouseName.isEmpty ? 'Your partner' : spouseName;
    final left = counts == null
        ? 0
        : widget.items.where((d) => (counts[d.id] ?? 0) < d.repeatCount).length;
    final status = [
      if (done || mine) 'Done — may Allah accept',
      if (spouseDone) '$spouse finished',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LovSurface(
          padding: EdgeInsets.zero,
          clip: true,
          child: counts == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  children: [
                    for (final (i, d) in widget.items.indexed) ...[
                      if (i > 0) Divider(height: 1, color: p.surface2),
                      _DhikrRow(
                        title: d.title,
                        n: counts[d.id] ?? 0,
                        of: d.repeatCount,
                        onTap: () => _tap(d),
                      ),
                    ],
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(
            status.isNotEmpty
                ? status.join(' · ')
                : 'Tap a row to count it. $left left.',
            style: TextStyle(
              fontSize: 12,
              color: status.isNotEmpty ? p.accent : p.muted,
            ),
          ),
        ),
      ],
    );
  }
}

class _DhikrRow extends StatelessWidget {
  const _DhikrRow({
    required this.title,
    required this.n,
    required this.of,
    required this.onTap,
  });

  final String title;
  final int n;
  final int of;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.lov;
    final full = n >= of;
    return Semantics(
      button: true,
      label: '$title, $n of $of',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: of == 0 ? 0 : n / of),
                        duration: const Duration(milliseconds: 400),
                        curve: const Cubic(.16, 1, .3, 1),
                        builder: (_, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 4,
                          color: p.accent,
                          backgroundColor: p.line,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 52,
                child: Text(
                  full ? 'Done' : '$n/$of',
                  textAlign: TextAlign.right,
                  style:
                      lovDisplay(
                        context,
                        size: 15,
                        color: full ? p.accent : p.muted,
                      ).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
