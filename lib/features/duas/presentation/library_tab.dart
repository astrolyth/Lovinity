import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../data/dua_library_repository.dart';
import '../domain/dua_library_providers.dart';
import '../domain/dua_search.dart';
import 'library_dua_sheet.dart';

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  String _query = '';
  String? _category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(duaLibraryProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Could not load', style: theme.textTheme.bodyMedium),
      ),
      data: (all) {
        if (all.isEmpty) {
          return Center(
            child: Text(
              'Duas are on their way.',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }
        final cats = {
          for (final d in all)
            if (d.category != null && !adhkarCategories.contains(d.category))
              d.category!,
        }.toList();
        final shown = searchLibrary(all, _query, category: _category);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: LovSpace.md),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search: eating, travel, rain…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final c in [null, ...cats])
                    Padding(
                      padding: const EdgeInsets.only(right: LovSpace.sm),
                      child: Center(
                        child: ChoiceChip(
                          label: Text(c ?? 'All'),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'No duas match "$_query".',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) => _row(shown[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(LibraryDua d) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(d.title),
    subtitle: Text(
      d.translation.split('\n').first,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => showLibraryDuaSheet(context, d),
  );
}
