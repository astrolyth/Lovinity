import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/adhkar_repository.dart';
import '../data/dua_library_repository.dart';
import '../domain/adhkar_providers.dart';
import '../domain/dua_library_providers.dart';
import 'library_tab.dart' show LibraryRetry;

class AdhkarTab extends ConsumerStatefulWidget {
  const AdhkarTab({super.key});

  @override
  ConsumerState<AdhkarTab> createState() => _AdhkarTabState();
}

class _AdhkarTabState extends ConsumerState<AdhkarTab> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayKey = ref.watch(adhkarTodayKeyProvider);
    final profile = ref.watch(ownProfileProvider);
    if (dayKey == null) {
      return profile.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Text(
                'Adhkar are on their way.',
                style: theme.textTheme.bodyMedium,
              ),
            );
    }
    return ref.watch(duaLibraryProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => const LibraryRetry(),
          data: (all) {
            final bySet = {
              for (final s in AdhkarSet.values)
                s: all.where((d) => d.category == s.dbValue).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
            };
            if (bySet.values.every((l) => l.isEmpty)) {
              return Center(
                child: Text(
                  'Adhkar are on their way.',
                  style: theme.textTheme.bodyMedium,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(LovSpace.lg),
              children: [
                for (final s in AdhkarSet.values)
                  if (bySet[s]!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: LovSpace.md),
                      // Keyed on the day so a rollover reloads progress.
                      child: _SetCard(
                        key: ValueKey('$dayKey|${s.dbValue}'),
                        set: s,
                        dayKey: dayKey,
                        items: bySet[s]!,
                      ),
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
    ref
        .read(adhkarProgressStoreProvider)
        .load(widget.dayKey, widget.set)
        .then((c) {
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
      await ref.read(adhkarRepositoryProvider).complete(
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
    final theme = Theme.of(context);
    final counts = _counts;
    final selfId =
        ref.watch(authSessionProvider.select((s) => s.asData?.value?.user.id));
    final coupleId =
        ref.watch(currentCoupleProvider.select((c) => c.asData?.value?.id));
    final completions = ref.watch(adhkarCompletionsProvider).asData?.value;
    final today = (completions ?? const <AdhkarCompletion>[])
        .where((c) => c.localDate == widget.dayKey && c.set == widget.set);
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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _complete(coupleId, selfId));
    }

    final spouseName = ref
            .watch(spouseProfileProvider.select((p) => p.asData?.value))
            ?.displayName ??
        '';
    final spouse = spouseName.isEmpty ? 'Your partner' : spouseName;

    return LovCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(widget.set.label, style: theme.textTheme.titleMedium),
        subtitle: (done || mine || spouseDone)
            ? Text([
                if (done || mine) 'Done — may Allah accept',
                if (spouseDone) '$spouse finished',
              ].join(' · '))
            : null,
        children: [
          if (counts == null)
            const Padding(
              padding: EdgeInsets.all(LovSpace.md),
              child: CircularProgressIndicator(),
            )
          else
            for (final d in widget.items)
              ListTile(
                title: Text(d.title),
                subtitle: Text(
                  d.translation,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _Ring(
                  n: counts[d.id] ?? 0,
                  of: d.repeatCount,
                ),
                onTap: () => _tap(d),
              ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.n, required this.of});
  final int n;
  final int of;

  @override
  Widget build(BuildContext context) {
    final full = n >= of;
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(value: n / of, strokeWidth: 3),
          full
              ? const Icon(Icons.check, size: 18)
              : Text('$n/$of', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
