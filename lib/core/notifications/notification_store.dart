// lib/core/notifications/notification_store.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../storage/signal_db.dart';

typedef NotificationRow = AppNotification;

class NotificationStore {
  NotificationStore(this._db);
  final SignalDb _db;

  /// Wrapped in a transaction so the "read max(seq), then insert" pair is
  /// atomic -- without this, two concurrent inserts could both read the same
  /// max and write the same `seq`, reintroducing the same-second ordering
  /// tie this column exists to prevent.
  Future<void> insert({
    required String kind,
    required String title,
    String? body,
    required String route,
  }) async {
    await _db.transaction(() async {
      final maxSeqExpr = _db.appNotifications.seq.max();
      final result = await (_db.selectOnly(_db.appNotifications)
            ..addColumns([maxSeqExpr]))
          .getSingleOrNull();
      final maxSeq = result?.read(maxSeqExpr) ?? 0;
      final nextSeq = maxSeq + 1;

      await _db.into(_db.appNotifications).insert(
            AppNotificationsCompanion.insert(
              id: const Uuid().v4(),
              kind: kind,
              title: title,
              body: Value(body),
              route: route,
              createdAt: DateTime.now(),
              seq: Value(nextSeq),
            ),
          );
    });
  }

  Stream<List<NotificationRow>> watchAll() {
    return (_db.select(_db.appNotifications)
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.seq),
          ]))
        .watch();
  }

  Stream<int> watchUnreadCount() {
    final count = _db.appNotifications.id.count();
    final q = _db.selectOnly(_db.appNotifications)
      ..addColumns([count])
      ..where(_db.appNotifications.readAt.isNull());
    return q.map((row) => row.read(count) ?? 0).watchSingle();
  }

  Future<void> markRead(String id) {
    return (_db.update(_db.appNotifications)..where((t) => t.id.equals(id)))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }

  Future<void> markAllRead() {
    return (_db.update(_db.appNotifications)
          ..where((t) => t.readAt.isNull()))
        .write(AppNotificationsCompanion(readAt: Value(DateTime.now())));
  }
}
