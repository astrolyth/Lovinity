import 'package:supabase_flutter/supabase_flutter.dart';

/// One line on the shared shopping list.
///
/// A row, not an element of a jsonb array — see
/// `20260807000003_grocery_items.sql`. Both spouses tick items at the same
/// time in a shop, and array-element updates lose one of every pair of
/// concurrent writes.
class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.listId,
    required this.name,
    required this.checked,
    required this.position,
    required this.createdBy,
    this.qty,
    this.checkedBy,
    this.checkedAt,
  });

  final String id;
  final String listId;
  final String name;
  final String? qty;
  final bool checked;

  /// Who ticked it — lets the list say "Aisha got this" instead of just
  /// greying the row, which is the difference between a shared list and two
  /// people editing the same document.
  final String? checkedBy;
  final DateTime? checkedAt;
  final int position;
  final String createdBy;

  factory GroceryItem.fromRow(Map<String, dynamic> row) => GroceryItem(
        id: row['id'] as String,
        listId: row['list_id'] as String,
        name: row['name'] as String,
        qty: row['qty'] as String?,
        checked: row['checked'] as bool? ?? false,
        checkedBy: row['checked_by'] as String?,
        checkedAt: row['checked_at'] == null
            ? null
            : DateTime.parse(row['checked_at'] as String),
        position: (row['position'] as num?)?.toInt() ?? 0,
        createdBy: row['created_by'] as String,
      );
}

class GroceryList {
  const GroceryList({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;

  factory GroceryList.fromRow(Map<String, dynamic> row) => GroceryList(
        id: row['id'] as String,
        title: (row['title'] ?? 'Groceries') as String,
        updatedAt: DateTime.parse(row['updated_at'] as String),
      );
}

class GroceryRepository {
  GroceryRepository(this._client);

  final SupabaseClient _client;

  Stream<List<GroceryList>> watchLists({required String coupleId}) {
    return _client
        .from('grocery_lists')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                GroceryList.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  /// Live items for the whole couple, ordered for display.
  ///
  /// Streams by `couple_id` rather than `list_id` so a single subscription
  /// covers every list — `.stream()` allows only one filter, and re-subscribing
  /// on each list switch would drop and rebuild the socket.
  Stream<List<GroceryItem>> watchItems({required String coupleId}) {
    return _client
        .from('grocery_items')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('position')
        .map((rows) => [
              for (final r in rows)
                GroceryItem.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<String> createList({
    required String coupleId,
    String title = 'Groceries',
  }) async {
    final row = await _client
        .from('grocery_lists')
        .insert({'couple_id': coupleId, 'title': title})
        .select()
        .single();
    return row['id'] as String;
  }

  Future<void> addItem({
    required String coupleId,
    required String listId,
    required String userId,
    required String name,
    String? qty,
    int position = 0,
  }) async {
    await _client.from('grocery_items').insert({
      'couple_id': coupleId,
      'list_id': listId,
      'created_by': userId,
      'name': name,
      if (qty != null && qty.isNotEmpty) 'qty': qty,
      'position': position,
    });
  }

  /// Ticks or un-ticks a single item.
  ///
  /// Scoped to one row by id, so two spouses ticking different items — or even
  /// racing on the same one — can never clobber each other's work.
  Future<void> setChecked({
    required String itemId,
    required String userId,
    required bool checked,
  }) async {
    await _client.from('grocery_items').update({
      'checked': checked,
      'checked_by': checked ? userId : null,
      'checked_at':
          checked ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq('id', itemId);
  }

  Future<void> deleteItem(String itemId) async {
    await _client.from('grocery_items').delete().eq('id', itemId);
  }

  /// Clears everything already bought, the usual end-of-shop action.
  Future<void> clearChecked({required String listId}) async {
    await _client
        .from('grocery_items')
        .delete()
        .eq('list_id', listId)
        .eq('checked', true);
  }
}
