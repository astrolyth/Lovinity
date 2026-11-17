import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../domain/tasbih_providers.dart';

class TasbihListScreen extends ConsumerWidget {
  const TasbihListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(tasbihCountersProvider);
    return LovScaffold(
      title: 'Tasbih together',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New goal'),
      ),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Could not load', style: theme.textTheme.bodyMedium)),
        data: (list) => list.isEmpty
            ? Center(
                child: Text(
                  'Set a shared dhikr goal — like 1,000 salawat this week.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(counterTotalsProvider),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
                  children: [
                    for (final c in list) _CounterTile(counter: c),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final couple = ref.read(currentCoupleProvider).asData?.value;
    if (couple == null) return;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LovRadius.lg)),
      ),
      builder: (_) => _CreateSheet(coupleId: couple.id),
    );
  }
}

class _CounterTile extends ConsumerWidget {
  const _CounterTile({required this.counter});
  final DhikrCounter counter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = ref.watch(counterTotalsProvider(counter.id)).asData?.value;
    final name = ref.watch(spouseProfileProvider).asData?.value?.displayName ??
        'Your partner';
    final total = totals?.total ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: LovSpace.md),
      child: LovCard(
        onTap: () => context.push('/home/tasbih/${counter.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(counter.title, style: theme.textTheme.titleMedium),
            if (counter.arabicText != null)
              Text(counter.arabicText!, style: theme.textTheme.titleLarge),
            const SizedBox(height: LovSpace.sm),
            LinearProgressIndicator(
              value: (total / counter.target).clamp(0.0, 1.0),
            ),
            const SizedBox(height: LovSpace.sm),
            Text(
              'You ${totals?.mine ?? 0} · $name ${totals?.spouse ?? 0}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateSheet extends ConsumerStatefulWidget {
  const _CreateSheet({required this.coupleId});
  final String coupleId;

  @override
  ConsumerState<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends ConsumerState<_CreateSheet> {
  final _title = TextEditingController();
  final _arabic = TextEditingController();
  final _target = TextEditingController(text: '100');
  String _period = 'weekly';
  bool _busy = false;
  bool _submitted = false;

  @override
  void dispose() {
    _title.dispose();
    _arabic.dispose();
    _target.dispose();
    super.dispose();
  }

  int? get _targetVal {
    final n = int.tryParse(_target.text.trim());
    return n != null && n > 0 ? n : null;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final target = _targetVal;
    if (_title.text.trim().isEmpty || target == null || _busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(tasbihRepositoryProvider).create(
            coupleId: widget.coupleId,
            title: _title.text.trim(),
            arabicText: _arabic.text.trim(),
            target: target,
            period: _period,
          );
      if (mounted) navigator.pop();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not create the goal')),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        LovSpace.lg,
        LovSpace.lg,
        LovSpace.lg,
        LovSpace.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _submitted && _title.text.trim().isEmpty
                    ? 'Title is required'
                    : null,
              ),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _arabic,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(labelText: 'Arabic (optional)'),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Target',
                errorText: _submitted && _targetVal == null
                    ? 'Enter a number above 0'
                    : null,
              ),
            ),
            Wrap(
              spacing: LovSpace.sm,
              children: [
                for (final n in const [33, 100, 1000])
                  ActionChip(
                    label: Text('$n'),
                    onPressed: () => setState(() => _target.text = '$n'),
                  ),
              ],
            ),
            const SizedBox(height: LovSpace.md),
            Wrap(
              spacing: LovSpace.sm,
              children: [
                for (final p in const [
                  ('daily', 'Daily'),
                  ('weekly', 'Weekly'),
                  ('monthly', 'Monthly'),
                  ('once', 'Once'),
                ])
                  ChoiceChip(
                    label: Text(p.$2),
                    selected: _period == p.$1,
                    onSelected: (_) => setState(() => _period = p.$1),
                  ),
              ],
            ),
            const SizedBox(height: LovSpace.lg),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
