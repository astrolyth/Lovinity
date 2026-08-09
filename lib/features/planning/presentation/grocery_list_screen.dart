import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/haptics.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/domain/auth_controller.dart';
import '../../home/domain/home_providers.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/grocery_repository.dart';
import '../domain/planning_providers.dart';

/// The live shared shopping list.
///
/// Every tick writes one row, so both spouses can work the aisles at the same
/// time without overwriting each other — see `20260807000003_grocery_items.sql`
/// for why the jsonb array this replaced could not do that.
class GroceryListScreen extends ConsumerStatefulWidget {
  const GroceryListScreen({super.key});

  @override
  ConsumerState<GroceryListScreen> createState() => _GroceryListScreenState();
}

class _GroceryListScreenState extends ConsumerState<GroceryListScreen> {
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(groceryItemsProvider);
    final list = ref.watch(activeGroceryListProvider);
    final items = ref.watch(activeGroceryItemsProvider);
    final spouse = ref.watch(spouseProfileProvider).asData?.value;
    final session = ref.watch(authSessionProvider).asData?.value;
    final outstanding = items.where((i) => !i.checked).length;

    return LovScaffold(
      title: 'Shopping list',
      subtitle: Text(
        outstanding == 0
            ? (items.isEmpty ? 'Nothing on the list' : 'All done 🤍')
            : '$outstanding to get',
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      actions: [
        if (items.any((i) => i.checked))
          IconButton(
            tooltip: 'Clear bought',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: list == null
                ? null
                : () => ref
                    .read(groceryRepositoryProvider)
                    .clearChecked(listId: list.id),
          ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: LovSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                      hintText: 'Add an item…',
                      prefixIcon: Icon(Icons.add),
                    ),
                  ),
                ),
                const SizedBox(width: LovSpace.sm),
                LovButton(
                  label: 'Add',
                  loading: _adding,
                  onPressed: _add,
                ),
              ],
            ),
          ),
          Expanded(
            child: itemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Could not load the list',
                    style: theme.textTheme.bodyMedium),
              ),
              data: (_) => items.isEmpty
                  ? const LovEmpty(
                      icon: Icons.shopping_basket_outlined,
                      title: 'The list is empty',
                      description:
                          'Add what you need. You will both see changes as '
                          'they happen.',
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _ItemTile(
                          item: item,
                          checkedByName: item.checkedBy == null
                              ? null
                              : item.checkedBy == session?.user.id
                                  ? 'You'
                                  : (spouse?.displayName ?? 'Your spouse'),
                          onToggle: () => _toggle(item),
                          onDelete: () => ref
                              .read(groceryRepositoryProvider)
                              .deleteItem(item.id),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(GroceryItem item) async {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session == null) return;
    unawaited(LovHaptics.light());
    await ref.read(groceryRepositoryProvider).setChecked(
          itemId: item.id,
          userId: session.user.id,
          checked: !item.checked,
        );
  }

  Future<void> _add() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    final session = ref.read(authSessionProvider).asData?.value;
    if (couple == null || session == null) return;

    setState(() => _adding = true);
    final repo = ref.read(groceryRepositoryProvider);
    try {
      // The list is created on first use rather than at pairing, so a couple
      // who never shops together never carries an empty row.
      var list = ref.read(activeGroceryListProvider);
      final listId =
          list?.id ?? await repo.createList(coupleId: couple.id);
      final existing = ref.read(activeGroceryItemsProvider);
      await repo.addItem(
        coupleId: couple.id,
        listId: listId,
        userId: session.user.id,
        name: name,
        position: existing.length,
      );
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add that item')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.checkedByName,
    required this.onToggle,
    required this.onDelete,
  });

  final GroceryItem item;
  final String? checkedByName;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: LovSpace.lg),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.error),
      ),
      child: CheckboxListTile(
        value: item.checked,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(
          item.qty == null || item.qty!.isEmpty
              ? item.name
              : '${item.name} · ${item.qty}',
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: item.checked ? TextDecoration.lineThrough : null,
            color: item.checked
                ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                : null,
          ),
        ),
        // Attribution is what makes this a shared list rather than a document
        // two people happen to edit.
        subtitle: item.checked && checkedByName != null
            ? Text('$checkedByName got this',
                style: theme.textTheme.labelSmall)
            : null,
      ),
    );
  }
}
