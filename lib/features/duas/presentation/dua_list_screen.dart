import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/motion/motion.dart';
import '../../../core/platform/haptics.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/dua_repository.dart';
import '../domain/dua_library_providers.dart';
import '../domain/dua_providers.dart';
import '../domain/dua_search.dart';
import 'adhkar_tab.dart';
import 'dua_for_today_card.dart';
import 'library_tab.dart';

class DuaListScreen extends ConsumerWidget {
  const DuaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = context.lov;
    final async = ref.watch(duasProvider);
    final cats =
        ref
            .watch(duaLibraryProvider)
            .asData
            ?.value
            .map((d) => d.category)
            .whereType<String>()
            .where((c) => !adhkarCategories.contains(c))
            .toSet()
            .toList() ??
        const <String>[];
    return LovPage(
      title: 'Duas',
      action: LovIconButton(
        icon: Icons.blur_circular_rounded,
        label: 'Tasbih together',
        onTap: () => context.push('/home/tasbih'),
      ),
      slivers: [
        const SliverToBoxAdapter(
          child: LovRise(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DuaForTodayCard(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: LovRise(
            delay: const Duration(milliseconds: 100),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Text('Adhkar', style: lovDisplay(context, size: 20)),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: LovRise(
            delay: Duration(milliseconds: 150),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AdhkarTab(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 4),
            child: TextButton(
              onPressed: () => _openLibrary(context),
              style: TextButton.styleFrom(foregroundColor: p.text),
              child: Row(
                children: [
                  Text('Library', style: lovDisplay(context, size: 20)),
                  const Spacer(),
                  Text(
                    'Search all',
                    style: TextStyle(fontSize: 13, color: p.accent),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.accent),
                ],
              ),
            ),
          ),
        ),
        if (cats.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: cats.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_titleCase(cats[i])),
                  onPressed: () => _openLibrary(context, category: cats[i]),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 4),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Our duas', style: lovDisplay(context, size: 20)),
                ),
                TextButton.icon(
                  onPressed: () => _openCompose(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add a dua'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(child: _ourList(theme, async)),
        ),
      ],
    );
  }

  void _openLibrary(BuildContext context, {String? category}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .85,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('All duas', style: lovDisplay(sheet, size: 21)),
              Expanded(child: LibraryTab(initialCategory: category)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ourList(ThemeData theme, AsyncValue<List<Dua>> async) {
    return async.when(
      loading: () => const _ListSkeleton(),
      error: (e, _) => Center(
        child: Text('Could not load', style: theme.textTheme.bodyMedium),
      ),
      data: (all) {
        final open = all.where((d) => !d.isAnswered).toList();
        final answered = all.where((d) => d.isAnswered).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (open.isEmpty && answered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: LovSpace.xxxl),
                  child: Center(
                    child: Text(
                      'No duas yet. Add one you both want to make.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              else ...[
                if (open.isNotEmpty) ...[
                  LovSectionHeader(title: 'Open (${open.length})'),
                  const SizedBox(height: LovSpace.sm),
                  LovStagger(
                    stagger: const Duration(milliseconds: 40),
                    children: [
                      for (final d in open)
                        Padding(
                          padding: const EdgeInsets.only(bottom: LovSpace.md),
                          child: _DuaTile(dua: d),
                        ),
                    ],
                  ),
                  const SizedBox(height: LovSpace.xl),
                ],
                if (answered.isNotEmpty) ...[
                  LovSectionHeader(
                    title: 'Answered (${answered.length})',
                    subtitle: 'Alḥamdulillah.',
                  ),
                  const SizedBox(height: LovSpace.sm),
                  LovStagger(
                    stagger: const Duration(milliseconds: 40),
                    children: [
                      for (final d in answered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: LovSpace.md),
                          child: _DuaTile(dua: d),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCompose(BuildContext context, WidgetRef ref) async {
    final theme = Theme.of(context);
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LovRadius.lg)),
      ),
      builder: (sheetContext) => _AddDuaSheet(
        onSubmit: (title, body, visibility) async {
          await ref
              .read(duaRepositoryProvider)
              .add(
                coupleId: couple.id,
                userId: session.user.id,
                title: title,
                body: body,
                visibility: visibility,
              );
          unawaited(LovHaptics.selection());
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

class _DuaTile extends ConsumerWidget {
  const _DuaTile({required this.dua});
  final Dua dua;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return LovCard(
      onTap: () => _openMarkAnswered(context, ref),
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleAnswered(ref),
            child: AnimatedContainer(
              duration: LovMotion.standard,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: dua.isAnswered
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
                border: dua.isAnswered
                    ? null
                    : Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: dua.isAnswered
                  ? Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: LovSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dua.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    decoration: dua.isAnswered
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.45,
                    ),
                    color: dua.isAnswered
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
                        : null,
                  ),
                ),
                if (dua.body != null && dua.body!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dua.body!,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (dua.isAnswered && dua.answeredAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Answered · ${DateFormat.MMMd().format(dua.answeredAt!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (dua.visibility == 'private')
            Padding(
              padding: const EdgeInsets.only(left: LovSpace.sm),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleAnswered(WidgetRef ref) async {
    final repo = ref.read(duaRepositoryProvider);
    unawaited(LovHaptics.selection());
    if (dua.isAnswered) {
      await repo.setUnanswered(dua.id);
    } else {
      await repo.setAnswered(dua.id);
    }
  }

  Future<void> _openMarkAnswered(BuildContext context, WidgetRef ref) async {
    if (dua.isAnswered) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as answered?'),
        content: Text(dua.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ref.read(duaRepositoryProvider).setAnswered(dua.id);
              unawaited(LovHaptics.medium());
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Alḥamdulillah'),
          ),
        ],
      ),
    );
  }
}

class _AddDuaSheet extends StatefulWidget {
  const _AddDuaSheet({required this.onSubmit});
  final Future<void> Function(String title, String? body, String visibility)
  onSubmit;

  @override
  State<_AddDuaSheet> createState() => _AddDuaSheetState();
}

class _AddDuaSheetState extends State<_AddDuaSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _visibility = 'shared';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        t,
        _body.text.trim().isEmpty ? null : _body.text.trim(),
        _visibility,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LovSpace.lg,
          LovSpace.xl,
          LovSpace.lg,
          LovSpace.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Add a dua', style: theme.textTheme.titleLarge),
            const SizedBox(height: LovSpace.lg),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'What are you asking for?',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _body,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'A little more (optional)',
              ),
            ),
            const SizedBox(height: LovSpace.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'shared',
                  label: Text('Shared'),
                  icon: Icon(Icons.favorite_outline_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'private',
                  label: Text('Private'),
                  icon: Icon(Icons.lock_outline_rounded, size: 16),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: (s) => setState(() => _visibility = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: LovSpace.lg),
            LovButton(
              label: 'Add',
              onPressed: _busy ? null : _submit,
              loading: _busy,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: LovSpace.lg),
      child: Column(
        children: [
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

String _titleCase(String s) => s.isEmpty
    ? s
    : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';
