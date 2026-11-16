import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'signal_db.g.dart';

/// Ratchet/session state. The identity PRIVATE key never lives here — it stays
/// in the Keychain (KeyVault). Keeping this in a DB (rather than scattered
/// Keychain entries) is what makes an encrypted backup feasible later.
class SignalSessions extends Table {
  TextColumn get name => text()();
  IntColumn get deviceNum => integer()();
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {name, deviceNum};
}

class SignalPrekeys extends Table {
  IntColumn get prekeyId => integer()();
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {prekeyId};
}

class SignalSignedPrekeys extends Table {
  IntColumn get signedPrekeyId => integer()();
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {signedPrekeyId};
}

class SignalIdentities extends Table {
  TextColumn get name => text()();
  IntColumn get deviceNum => integer()();
  BlobColumn get identityKey => blob()();
  DateTimeColumn get firstSeen => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {name, deviceNum};
}

/// Recorded when a known address presents a different identity key, so chat can
/// surface "their security code changed".
class SignalIdentityChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get deviceNum => integer()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Small key/value store for device-local counters (monotonic key ids).
/// Lives in the DB rather than the Keychain: it is state, not a secret, and it
/// shares a lifecycle with the prekeys it numbers.
class SignalMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Durable local chat history. Chat decryption is one-shot (Signal ratchet
/// consumes each message), so the plaintext is persisted here — consistent
/// with the rest of this DB, which already stores Signal key material.
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get senderId => text()();
  TextColumn get body => text().nullable()();
  TextColumn get replyToMessageId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();
  TextColumn get status => text()(); // sending|sent|delivered|read|failed
  // Attachment fields -- all null for a plain text message. attachmentKind
  // is 'photo' | 'video' | null.
  TextColumn get attachmentKind => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get sizeBytes => integer().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get storageKey => text().nullable()();
  BlobColumn get encKey => blob().nullable()();
  BlobColumn get nonce => blob().nullable()();
  BlobColumn get thumbnailBytes => blob().nullable()();
  TextColumn get localMediaPath => text().nullable()();
  TextColumn get downloadStatus => text().nullable()(); // none|downloading|downloaded|failed
  @override
  Set<Column> get primaryKey => {id};
}

class ChatReactions extends Table {
  TextColumn get messageId => text()();
  TextColumn get reactorId => text()();
  TextColumn get emoji => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {messageId, reactorId, emoji};
}

/// Persisted local activity feed: pairing, prayer check-ins, shared cycle
/// updates, daily question answers, shared duas, and revealed gratitude
/// notes (see docs/superpowers/specs/2026-08-01-notification-inbox-v2-design.md).
/// Deliberately excludes chat messages/reactions -- those already have their
/// own unread badge on the chat button. Named `AppNotifications`, not
/// `Notifications` -- Drift would otherwise generate a row class literally
/// called `Notification`, colliding with `package:flutter/widgets.dart`'s own
/// `Notification` class wherever this table and Flutter widgets are imported
/// together.
///
/// Uses `seq` as a monotonic insertion sequence number to provide stable
/// ordering among notifications created in the same second (Drift's
/// DateTimeColumn maps to second-precision SQL, not millisecond precision) --
/// see `NotificationStore.insert`/`watchAll` (Task 2) for how it's used.
class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'pairing'|'prayer'|'cycle'|'question'|'dua'|'gratitude'
  TextColumn get title => text()();
  TextColumn get body => text().nullable()();
  TextColumn get route => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get readAt => dateTime().nullable()();
  IntColumn get seq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  SignalSessions,
  SignalPrekeys,
  SignalSignedPrekeys,
  SignalIdentities,
  SignalIdentityChanges,
  SignalMeta,
  ChatMessages,
  ChatReactions,
  AppNotifications,
])
class SignalDb extends _$SignalDb {
  /// One on-disk database PER ACCOUNT. Chat history and Signal state are
  /// local-only (the server copy is single-use ciphertext), so isolating them
  /// by file is what lets several accounts share a device: switching accounts
  /// never has to wipe anything, nobody can read another account's history,
  /// and each account keeps its own identity + device number.
  SignalDb.forUser(String userId)
      : super(driftDatabase(name: 'lovinity_signal_$userId'));

  /// In-memory instance for tests.
  SignalDb.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(signalMeta);
          if (from < 3) {
            await m.createTable(chatMessages);
            await m.createTable(chatReactions);
          }
          if (from < 4) {
            await m.addColumn(chatMessages, chatMessages.attachmentKind);
            await m.addColumn(chatMessages, chatMessages.mimeType);
            await m.addColumn(chatMessages, chatMessages.sizeBytes);
            await m.addColumn(chatMessages, chatMessages.width);
            await m.addColumn(chatMessages, chatMessages.height);
            await m.addColumn(chatMessages, chatMessages.durationMs);
            await m.addColumn(chatMessages, chatMessages.storageKey);
            await m.addColumn(chatMessages, chatMessages.encKey);
            await m.addColumn(chatMessages, chatMessages.nonce);
            await m.addColumn(chatMessages, chatMessages.thumbnailBytes);
            await m.addColumn(chatMessages, chatMessages.localMediaPath);
            await m.addColumn(chatMessages, chatMessages.downloadStatus);
          }
          if (from < 5) await m.createTable(appNotifications);
        },
      );
}
