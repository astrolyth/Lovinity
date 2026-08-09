import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a date happens. `virtual` is what keeps the feature usable for
/// long-distance and travelling couples rather than only co-located ones.
enum DateSetting { home, out, virtual }

extension DateSettingX on DateSetting {
  String get dbValue => switch (this) {
        DateSetting.home => 'home',
        DateSetting.out => 'out',
        DateSetting.virtual => 'virtual',
      };

  String get label => switch (this) {
        DateSetting.home => 'At home',
        DateSetting.out => 'Out',
        DateSetting.virtual => 'Apart',
      };

  static DateSetting fromDb(String? v) => switch (v) {
        'out' => DateSetting.out,
        'virtual' => DateSetting.virtual,
        _ => DateSetting.home,
      };
}

class DateIdea {
  const DateIdea({
    required this.id,
    required this.title,
    required this.description,
    required this.setting,
    required this.effort,
    required this.costBand,
    this.category,
  });

  final String id;
  final String title;
  final String description;
  final DateSetting setting;
  final String effort;
  final String costBand;
  final String? category;

  bool get isFree => costBand == 'free';

  factory DateIdea.fromRow(Map<String, dynamic> row) => DateIdea(
        id: row['id'] as String,
        title: row['title'] as String,
        description: row['description'] as String,
        setting: DateSettingX.fromDb(row['setting'] as String?),
        effort: (row['effort'] ?? 'low') as String,
        costBand: (row['cost_band'] ?? 'free') as String,
        category: row['category'] as String?,
      );
}

/// An idea a couple has saved, and possibly scheduled or done.
class DateSave {
  const DateSave({
    required this.id,
    required this.ideaId,
    required this.savedBy,
    this.plannedFor,
    this.completedAt,
    this.notes,
  });

  final String id;
  final String ideaId;
  final String savedBy;
  final DateTime? plannedFor;
  final DateTime? completedAt;
  final String? notes;

  bool get isPlanned => plannedFor != null && completedAt == null;
  bool get isDone => completedAt != null;

  factory DateSave.fromRow(Map<String, dynamic> row) => DateSave(
        id: row['id'] as String,
        ideaId: row['idea_id'] as String,
        savedBy: row['saved_by'] as String,
        plannedFor: row['planned_for'] == null
            ? null
            : DateTime.parse(row['planned_for'] as String),
        completedAt: row['completed_at'] == null
            ? null
            : DateTime.parse(row['completed_at'] as String),
        notes: row['notes'] as String?,
      );
}

class DateRepository {
  DateRepository(this._client);

  final SupabaseClient _client;

  /// The idea library. Approved rows only, enforced by RLS (`date_ideas_read`).
  Future<List<DateIdea>> fetchIdeas() async {
    final rows = await _client.from('date_ideas').select().order('title');
    return [
      for (final r in rows)
        DateIdea.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Stream<List<DateSave>> watchSaves({required String coupleId}) {
    return _client
        .from('date_idea_saves')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .map((rows) => [
              for (final r in rows)
                DateSave.fromRow(Map<String, dynamic>.from(r)),
            ]);
  }

  Future<void> save({
    required String coupleId,
    required String ideaId,
    required String userId,
  }) async {
    await _client.from('date_idea_saves').upsert(
      {'couple_id': coupleId, 'idea_id': ideaId, 'saved_by': userId},
      onConflict: 'couple_id,idea_id',
    );
  }

  Future<void> unsave({required String saveId}) async {
    await _client.from('date_idea_saves').delete().eq('id', saveId);
  }

  /// Schedules a saved idea. [plannedFor] is a calendar date, not an instant —
  /// "we're doing this on Friday" means the same Friday for both of them.
  Future<void> plan({
    required String saveId,
    required DateTime? plannedFor,
  }) async {
    await _client.from('date_idea_saves').update({
      'planned_for': plannedFor == null
          ? null
          : '${plannedFor.year.toString().padLeft(4, '0')}-'
              '${plannedFor.month.toString().padLeft(2, '0')}-'
              '${plannedFor.day.toString().padLeft(2, '0')}',
    }).eq('id', saveId);
  }

  Future<void> markDone({required String saveId, String? notes}) async {
    await _client.from('date_idea_saves').update({
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    }).eq('id', saveId);
  }
}
