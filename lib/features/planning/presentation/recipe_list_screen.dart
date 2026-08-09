import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/widgets.dart';
import '../../pairing/domain/pairing_providers.dart';
import '../data/recipe_repository.dart';
import '../domain/planning_providers.dart';

/// Saved recipes, and the sheet for adding or editing one.
class RecipeListScreen extends ConsumerWidget {
  const RecipeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recipesAsync = ref.watch(recipesProvider);

    return LovScaffold(
      title: 'Recipes',
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showRecipeEditor(context, ref),
        child: const Icon(Icons.add),
      ),
      child: recipesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load recipes',
              style: theme.textTheme.bodyMedium),
        ),
        data: (recipes) => recipes.isEmpty
            ? const LovEmpty(
                icon: Icons.menu_book_outlined,
                title: 'No recipes yet',
                description:
                    'Save what you cook together, with any halal '
                    'substitutions worth remembering.',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: LovSpace.lg),
                itemCount: recipes.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: LovSpace.md),
                  child: _RecipeTile(recipe: recipes[index]),
                ),
              ),
      ),
    );
  }
}

class _RecipeTile extends ConsumerWidget {
  const _RecipeTile({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return LovCard(
      variant: LovCardVariant.plain,
      onTap: () => showRecipeEditor(context, ref, existing: recipe),
      padding: const EdgeInsets.all(LovSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(recipe.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            [
              if (recipe.ingredients.isNotEmpty)
                '${recipe.ingredients.length} ingredients',
              if (recipe.steps.isNotEmpty) '${recipe.steps.length} steps',
              if (recipe.sourceUrl != null) 'saved from a link',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (recipe.halalNotes != null && recipe.halalNotes!.isNotEmpty) ...[
            const SizedBox(height: LovSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: theme.colorScheme.secondary),
                const SizedBox(width: LovSpace.xs),
                Expanded(
                  child: Text(
                    recipe.halalNotes!,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Create or edit a recipe. Pass [sourceUrl] to pre-fill when saving from the
/// feed.
Future<void> showRecipeEditor(
  BuildContext context,
  WidgetRef ref, {
  Recipe? existing,
  String? sourceUrl,
  String? initialTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RecipeEditorSheet(
      existing: existing,
      sourceUrl: sourceUrl,
      initialTitle: initialTitle,
    ),
  );
}

class _RecipeEditorSheet extends ConsumerStatefulWidget {
  const _RecipeEditorSheet({this.existing, this.sourceUrl, this.initialTitle});

  final Recipe? existing;
  final String? sourceUrl;
  final String? initialTitle;

  @override
  ConsumerState<_RecipeEditorSheet> createState() => _RecipeEditorSheetState();
}

class _RecipeEditorSheetState extends ConsumerState<_RecipeEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _ingredients;
  late final TextEditingController _steps;
  late final TextEditingController _halalNotes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? widget.initialTitle ?? '');
    _ingredients =
        TextEditingController(text: (e?.ingredients ?? const []).join('\n'));
    _steps = TextEditingController(text: (e?.steps ?? const []).join('\n'));
    _halalNotes = TextEditingController(text: e?.halalNotes ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _halalNotes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: LovSpace.lg,
        right: LovSpace.lg,
        top: LovSpace.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + LovSpace.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEditing ? 'Edit recipe' : 'New recipe',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: LovSpace.lg),
            TextField(
              controller: _title,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _ingredients,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Ingredients',
                hintText: 'One per line',
              ),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _steps,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Steps',
                hintText: 'One per line',
              ),
            ),
            const SizedBox(height: LovSpace.md),
            TextField(
              controller: _halalNotes,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Halal notes (optional)',
                hintText: 'Substitutions worth remembering',
              ),
            ),
            const SizedBox(height: LovSpace.xl),
            LovButton(
              label: isEditing ? 'Save changes' : 'Save recipe',
              loading: _saving,
              expand: true,
              onPressed: _save,
            ),
            if (isEditing) ...[
              const SizedBox(height: LovSpace.sm),
              LovButton(
                label: 'Delete',
                variant: LovButtonVariant.text,
                expand: true,
                onPressed: _saving ? null : _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _lines(TextEditingController c) => [
        for (final line in c.text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final couple = ref.read(currentCoupleProvider).asData?.value;
    if (couple == null) return;
    setState(() => _saving = true);
    final repo = ref.read(recipeRepositoryProvider);
    try {
      if (widget.existing case final existing?) {
        await repo.update(
          id: existing.id,
          title: _title.text.trim(),
          ingredients: _lines(_ingredients),
          steps: _lines(_steps),
          sourceUrl: existing.sourceUrl,
          halalNotes: _halalNotes.text.trim(),
        );
      } else {
        await repo.save(
          coupleId: couple.id,
          title: _title.text.trim(),
          ingredients: _lines(_ingredients),
          steps: _lines(_steps),
          sourceUrl: widget.sourceUrl,
          halalNotes: _halalNotes.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the recipe')),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(recipeRepositoryProvider).delete(existing.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }
}
