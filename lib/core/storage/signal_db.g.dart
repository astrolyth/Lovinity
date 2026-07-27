// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'signal_db.dart';

// ignore_for_file: type=lint
class $SignalSessionsTable extends SignalSessions
    with TableInfo<$SignalSessionsTable, SignalSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNumMeta = const VerificationMeta(
    'deviceNum',
  );
  @override
  late final GeneratedColumn<int> deviceNum = GeneratedColumn<int>(
    'device_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordMeta = const VerificationMeta('record');
  @override
  late final GeneratedColumn<Uint8List> record = GeneratedColumn<Uint8List>(
    'record',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [name, deviceNum, record];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('device_num')) {
      context.handle(
        _deviceNumMeta,
        deviceNum.isAcceptableOrUnknown(data['device_num']!, _deviceNumMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNumMeta);
    }
    if (data.containsKey('record')) {
      context.handle(
        _recordMeta,
        record.isAcceptableOrUnknown(data['record']!, _recordMeta),
      );
    } else if (isInserting) {
      context.missing(_recordMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name, deviceNum};
  @override
  SignalSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalSession(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      deviceNum: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_num'],
      )!,
      record: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record'],
      )!,
    );
  }

  @override
  $SignalSessionsTable createAlias(String alias) {
    return $SignalSessionsTable(attachedDatabase, alias);
  }
}

class SignalSession extends DataClass implements Insertable<SignalSession> {
  final String name;
  final int deviceNum;
  final Uint8List record;
  const SignalSession({
    required this.name,
    required this.deviceNum,
    required this.record,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['device_num'] = Variable<int>(deviceNum);
    map['record'] = Variable<Uint8List>(record);
    return map;
  }

  SignalSessionsCompanion toCompanion(bool nullToAbsent) {
    return SignalSessionsCompanion(
      name: Value(name),
      deviceNum: Value(deviceNum),
      record: Value(record),
    );
  }

  factory SignalSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalSession(
      name: serializer.fromJson<String>(json['name']),
      deviceNum: serializer.fromJson<int>(json['deviceNum']),
      record: serializer.fromJson<Uint8List>(json['record']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'deviceNum': serializer.toJson<int>(deviceNum),
      'record': serializer.toJson<Uint8List>(record),
    };
  }

  SignalSession copyWith({String? name, int? deviceNum, Uint8List? record}) =>
      SignalSession(
        name: name ?? this.name,
        deviceNum: deviceNum ?? this.deviceNum,
        record: record ?? this.record,
      );
  SignalSession copyWithCompanion(SignalSessionsCompanion data) {
    return SignalSession(
      name: data.name.present ? data.name.value : this.name,
      deviceNum: data.deviceNum.present ? data.deviceNum.value : this.deviceNum,
      record: data.record.present ? data.record.value : this.record,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalSession(')
          ..write('name: $name, ')
          ..write('deviceNum: $deviceNum, ')
          ..write('record: $record')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(name, deviceNum, $driftBlobEquality.hash(record));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalSession &&
          other.name == this.name &&
          other.deviceNum == this.deviceNum &&
          $driftBlobEquality.equals(other.record, this.record));
}

class SignalSessionsCompanion extends UpdateCompanion<SignalSession> {
  final Value<String> name;
  final Value<int> deviceNum;
  final Value<Uint8List> record;
  final Value<int> rowid;
  const SignalSessionsCompanion({
    this.name = const Value.absent(),
    this.deviceNum = const Value.absent(),
    this.record = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignalSessionsCompanion.insert({
    required String name,
    required int deviceNum,
    required Uint8List record,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       deviceNum = Value(deviceNum),
       record = Value(record);
  static Insertable<SignalSession> custom({
    Expression<String>? name,
    Expression<int>? deviceNum,
    Expression<Uint8List>? record,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (deviceNum != null) 'device_num': deviceNum,
      if (record != null) 'record': record,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignalSessionsCompanion copyWith({
    Value<String>? name,
    Value<int>? deviceNum,
    Value<Uint8List>? record,
    Value<int>? rowid,
  }) {
    return SignalSessionsCompanion(
      name: name ?? this.name,
      deviceNum: deviceNum ?? this.deviceNum,
      record: record ?? this.record,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (deviceNum.present) {
      map['device_num'] = Variable<int>(deviceNum.value);
    }
    if (record.present) {
      map['record'] = Variable<Uint8List>(record.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalSessionsCompanion(')
          ..write('name: $name, ')
          ..write('deviceNum: $deviceNum, ')
          ..write('record: $record, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SignalPrekeysTable extends SignalPrekeys
    with TableInfo<$SignalPrekeysTable, SignalPrekey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalPrekeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _prekeyIdMeta = const VerificationMeta(
    'prekeyId',
  );
  @override
  late final GeneratedColumn<int> prekeyId = GeneratedColumn<int>(
    'prekey_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordMeta = const VerificationMeta('record');
  @override
  late final GeneratedColumn<Uint8List> record = GeneratedColumn<Uint8List>(
    'record',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [prekeyId, record];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_prekeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalPrekey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('prekey_id')) {
      context.handle(
        _prekeyIdMeta,
        prekeyId.isAcceptableOrUnknown(data['prekey_id']!, _prekeyIdMeta),
      );
    }
    if (data.containsKey('record')) {
      context.handle(
        _recordMeta,
        record.isAcceptableOrUnknown(data['record']!, _recordMeta),
      );
    } else if (isInserting) {
      context.missing(_recordMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {prekeyId};
  @override
  SignalPrekey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalPrekey(
      prekeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}prekey_id'],
      )!,
      record: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record'],
      )!,
    );
  }

  @override
  $SignalPrekeysTable createAlias(String alias) {
    return $SignalPrekeysTable(attachedDatabase, alias);
  }
}

class SignalPrekey extends DataClass implements Insertable<SignalPrekey> {
  final int prekeyId;
  final Uint8List record;
  const SignalPrekey({required this.prekeyId, required this.record});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['prekey_id'] = Variable<int>(prekeyId);
    map['record'] = Variable<Uint8List>(record);
    return map;
  }

  SignalPrekeysCompanion toCompanion(bool nullToAbsent) {
    return SignalPrekeysCompanion(
      prekeyId: Value(prekeyId),
      record: Value(record),
    );
  }

  factory SignalPrekey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalPrekey(
      prekeyId: serializer.fromJson<int>(json['prekeyId']),
      record: serializer.fromJson<Uint8List>(json['record']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'prekeyId': serializer.toJson<int>(prekeyId),
      'record': serializer.toJson<Uint8List>(record),
    };
  }

  SignalPrekey copyWith({int? prekeyId, Uint8List? record}) => SignalPrekey(
    prekeyId: prekeyId ?? this.prekeyId,
    record: record ?? this.record,
  );
  SignalPrekey copyWithCompanion(SignalPrekeysCompanion data) {
    return SignalPrekey(
      prekeyId: data.prekeyId.present ? data.prekeyId.value : this.prekeyId,
      record: data.record.present ? data.record.value : this.record,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalPrekey(')
          ..write('prekeyId: $prekeyId, ')
          ..write('record: $record')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(prekeyId, $driftBlobEquality.hash(record));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalPrekey &&
          other.prekeyId == this.prekeyId &&
          $driftBlobEquality.equals(other.record, this.record));
}

class SignalPrekeysCompanion extends UpdateCompanion<SignalPrekey> {
  final Value<int> prekeyId;
  final Value<Uint8List> record;
  const SignalPrekeysCompanion({
    this.prekeyId = const Value.absent(),
    this.record = const Value.absent(),
  });
  SignalPrekeysCompanion.insert({
    this.prekeyId = const Value.absent(),
    required Uint8List record,
  }) : record = Value(record);
  static Insertable<SignalPrekey> custom({
    Expression<int>? prekeyId,
    Expression<Uint8List>? record,
  }) {
    return RawValuesInsertable({
      if (prekeyId != null) 'prekey_id': prekeyId,
      if (record != null) 'record': record,
    });
  }

  SignalPrekeysCompanion copyWith({
    Value<int>? prekeyId,
    Value<Uint8List>? record,
  }) {
    return SignalPrekeysCompanion(
      prekeyId: prekeyId ?? this.prekeyId,
      record: record ?? this.record,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (prekeyId.present) {
      map['prekey_id'] = Variable<int>(prekeyId.value);
    }
    if (record.present) {
      map['record'] = Variable<Uint8List>(record.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalPrekeysCompanion(')
          ..write('prekeyId: $prekeyId, ')
          ..write('record: $record')
          ..write(')'))
        .toString();
  }
}

class $SignalSignedPrekeysTable extends SignalSignedPrekeys
    with TableInfo<$SignalSignedPrekeysTable, SignalSignedPrekey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalSignedPrekeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _signedPrekeyIdMeta = const VerificationMeta(
    'signedPrekeyId',
  );
  @override
  late final GeneratedColumn<int> signedPrekeyId = GeneratedColumn<int>(
    'signed_prekey_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordMeta = const VerificationMeta('record');
  @override
  late final GeneratedColumn<Uint8List> record = GeneratedColumn<Uint8List>(
    'record',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [signedPrekeyId, record];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_signed_prekeys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalSignedPrekey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('signed_prekey_id')) {
      context.handle(
        _signedPrekeyIdMeta,
        signedPrekeyId.isAcceptableOrUnknown(
          data['signed_prekey_id']!,
          _signedPrekeyIdMeta,
        ),
      );
    }
    if (data.containsKey('record')) {
      context.handle(
        _recordMeta,
        record.isAcceptableOrUnknown(data['record']!, _recordMeta),
      );
    } else if (isInserting) {
      context.missing(_recordMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {signedPrekeyId};
  @override
  SignalSignedPrekey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalSignedPrekey(
      signedPrekeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}signed_prekey_id'],
      )!,
      record: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}record'],
      )!,
    );
  }

  @override
  $SignalSignedPrekeysTable createAlias(String alias) {
    return $SignalSignedPrekeysTable(attachedDatabase, alias);
  }
}

class SignalSignedPrekey extends DataClass
    implements Insertable<SignalSignedPrekey> {
  final int signedPrekeyId;
  final Uint8List record;
  const SignalSignedPrekey({
    required this.signedPrekeyId,
    required this.record,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['signed_prekey_id'] = Variable<int>(signedPrekeyId);
    map['record'] = Variable<Uint8List>(record);
    return map;
  }

  SignalSignedPrekeysCompanion toCompanion(bool nullToAbsent) {
    return SignalSignedPrekeysCompanion(
      signedPrekeyId: Value(signedPrekeyId),
      record: Value(record),
    );
  }

  factory SignalSignedPrekey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalSignedPrekey(
      signedPrekeyId: serializer.fromJson<int>(json['signedPrekeyId']),
      record: serializer.fromJson<Uint8List>(json['record']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'signedPrekeyId': serializer.toJson<int>(signedPrekeyId),
      'record': serializer.toJson<Uint8List>(record),
    };
  }

  SignalSignedPrekey copyWith({int? signedPrekeyId, Uint8List? record}) =>
      SignalSignedPrekey(
        signedPrekeyId: signedPrekeyId ?? this.signedPrekeyId,
        record: record ?? this.record,
      );
  SignalSignedPrekey copyWithCompanion(SignalSignedPrekeysCompanion data) {
    return SignalSignedPrekey(
      signedPrekeyId: data.signedPrekeyId.present
          ? data.signedPrekeyId.value
          : this.signedPrekeyId,
      record: data.record.present ? data.record.value : this.record,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalSignedPrekey(')
          ..write('signedPrekeyId: $signedPrekeyId, ')
          ..write('record: $record')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(signedPrekeyId, $driftBlobEquality.hash(record));
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalSignedPrekey &&
          other.signedPrekeyId == this.signedPrekeyId &&
          $driftBlobEquality.equals(other.record, this.record));
}

class SignalSignedPrekeysCompanion extends UpdateCompanion<SignalSignedPrekey> {
  final Value<int> signedPrekeyId;
  final Value<Uint8List> record;
  const SignalSignedPrekeysCompanion({
    this.signedPrekeyId = const Value.absent(),
    this.record = const Value.absent(),
  });
  SignalSignedPrekeysCompanion.insert({
    this.signedPrekeyId = const Value.absent(),
    required Uint8List record,
  }) : record = Value(record);
  static Insertable<SignalSignedPrekey> custom({
    Expression<int>? signedPrekeyId,
    Expression<Uint8List>? record,
  }) {
    return RawValuesInsertable({
      if (signedPrekeyId != null) 'signed_prekey_id': signedPrekeyId,
      if (record != null) 'record': record,
    });
  }

  SignalSignedPrekeysCompanion copyWith({
    Value<int>? signedPrekeyId,
    Value<Uint8List>? record,
  }) {
    return SignalSignedPrekeysCompanion(
      signedPrekeyId: signedPrekeyId ?? this.signedPrekeyId,
      record: record ?? this.record,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (signedPrekeyId.present) {
      map['signed_prekey_id'] = Variable<int>(signedPrekeyId.value);
    }
    if (record.present) {
      map['record'] = Variable<Uint8List>(record.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalSignedPrekeysCompanion(')
          ..write('signedPrekeyId: $signedPrekeyId, ')
          ..write('record: $record')
          ..write(')'))
        .toString();
  }
}

class $SignalIdentitiesTable extends SignalIdentities
    with TableInfo<$SignalIdentitiesTable, SignalIdentity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalIdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNumMeta = const VerificationMeta(
    'deviceNum',
  );
  @override
  late final GeneratedColumn<int> deviceNum = GeneratedColumn<int>(
    'device_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<Uint8List> identityKey =
      GeneratedColumn<Uint8List>(
        'identity_key',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>(
    'first_seen',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    name,
    deviceNum,
    identityKey,
    firstSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalIdentity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('device_num')) {
      context.handle(
        _deviceNumMeta,
        deviceNum.isAcceptableOrUnknown(data['device_num']!, _deviceNumMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNumMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name, deviceNum};
  @override
  SignalIdentity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalIdentity(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      deviceNum: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_num'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}identity_key'],
      )!,
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen'],
      )!,
    );
  }

  @override
  $SignalIdentitiesTable createAlias(String alias) {
    return $SignalIdentitiesTable(attachedDatabase, alias);
  }
}

class SignalIdentity extends DataClass implements Insertable<SignalIdentity> {
  final String name;
  final int deviceNum;
  final Uint8List identityKey;
  final DateTime firstSeen;
  const SignalIdentity({
    required this.name,
    required this.deviceNum,
    required this.identityKey,
    required this.firstSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['device_num'] = Variable<int>(deviceNum);
    map['identity_key'] = Variable<Uint8List>(identityKey);
    map['first_seen'] = Variable<DateTime>(firstSeen);
    return map;
  }

  SignalIdentitiesCompanion toCompanion(bool nullToAbsent) {
    return SignalIdentitiesCompanion(
      name: Value(name),
      deviceNum: Value(deviceNum),
      identityKey: Value(identityKey),
      firstSeen: Value(firstSeen),
    );
  }

  factory SignalIdentity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalIdentity(
      name: serializer.fromJson<String>(json['name']),
      deviceNum: serializer.fromJson<int>(json['deviceNum']),
      identityKey: serializer.fromJson<Uint8List>(json['identityKey']),
      firstSeen: serializer.fromJson<DateTime>(json['firstSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'deviceNum': serializer.toJson<int>(deviceNum),
      'identityKey': serializer.toJson<Uint8List>(identityKey),
      'firstSeen': serializer.toJson<DateTime>(firstSeen),
    };
  }

  SignalIdentity copyWith({
    String? name,
    int? deviceNum,
    Uint8List? identityKey,
    DateTime? firstSeen,
  }) => SignalIdentity(
    name: name ?? this.name,
    deviceNum: deviceNum ?? this.deviceNum,
    identityKey: identityKey ?? this.identityKey,
    firstSeen: firstSeen ?? this.firstSeen,
  );
  SignalIdentity copyWithCompanion(SignalIdentitiesCompanion data) {
    return SignalIdentity(
      name: data.name.present ? data.name.value : this.name,
      deviceNum: data.deviceNum.present ? data.deviceNum.value : this.deviceNum,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalIdentity(')
          ..write('name: $name, ')
          ..write('deviceNum: $deviceNum, ')
          ..write('identityKey: $identityKey, ')
          ..write('firstSeen: $firstSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    name,
    deviceNum,
    $driftBlobEquality.hash(identityKey),
    firstSeen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalIdentity &&
          other.name == this.name &&
          other.deviceNum == this.deviceNum &&
          $driftBlobEquality.equals(other.identityKey, this.identityKey) &&
          other.firstSeen == this.firstSeen);
}

class SignalIdentitiesCompanion extends UpdateCompanion<SignalIdentity> {
  final Value<String> name;
  final Value<int> deviceNum;
  final Value<Uint8List> identityKey;
  final Value<DateTime> firstSeen;
  final Value<int> rowid;
  const SignalIdentitiesCompanion({
    this.name = const Value.absent(),
    this.deviceNum = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignalIdentitiesCompanion.insert({
    required String name,
    required int deviceNum,
    required Uint8List identityKey,
    this.firstSeen = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       deviceNum = Value(deviceNum),
       identityKey = Value(identityKey);
  static Insertable<SignalIdentity> custom({
    Expression<String>? name,
    Expression<int>? deviceNum,
    Expression<Uint8List>? identityKey,
    Expression<DateTime>? firstSeen,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (deviceNum != null) 'device_num': deviceNum,
      if (identityKey != null) 'identity_key': identityKey,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignalIdentitiesCompanion copyWith({
    Value<String>? name,
    Value<int>? deviceNum,
    Value<Uint8List>? identityKey,
    Value<DateTime>? firstSeen,
    Value<int>? rowid,
  }) {
    return SignalIdentitiesCompanion(
      name: name ?? this.name,
      deviceNum: deviceNum ?? this.deviceNum,
      identityKey: identityKey ?? this.identityKey,
      firstSeen: firstSeen ?? this.firstSeen,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (deviceNum.present) {
      map['device_num'] = Variable<int>(deviceNum.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<Uint8List>(identityKey.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<DateTime>(firstSeen.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalIdentitiesCompanion(')
          ..write('name: $name, ')
          ..write('deviceNum: $deviceNum, ')
          ..write('identityKey: $identityKey, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SignalIdentityChangesTable extends SignalIdentityChanges
    with TableInfo<$SignalIdentityChangesTable, SignalIdentityChange> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalIdentityChangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNumMeta = const VerificationMeta(
    'deviceNum',
  );
  @override
  late final GeneratedColumn<int> deviceNum = GeneratedColumn<int>(
    'device_num',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changedAtMeta = const VerificationMeta(
    'changedAt',
  );
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
    'changed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, deviceNum, changedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_identity_changes';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalIdentityChange> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('device_num')) {
      context.handle(
        _deviceNumMeta,
        deviceNum.isAcceptableOrUnknown(data['device_num']!, _deviceNumMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNumMeta);
    }
    if (data.containsKey('changed_at')) {
      context.handle(
        _changedAtMeta,
        changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SignalIdentityChange map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalIdentityChange(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      deviceNum: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_num'],
      )!,
      changedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_at'],
      )!,
    );
  }

  @override
  $SignalIdentityChangesTable createAlias(String alias) {
    return $SignalIdentityChangesTable(attachedDatabase, alias);
  }
}

class SignalIdentityChange extends DataClass
    implements Insertable<SignalIdentityChange> {
  final int id;
  final String name;
  final int deviceNum;
  final DateTime changedAt;
  const SignalIdentityChange({
    required this.id,
    required this.name,
    required this.deviceNum,
    required this.changedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['device_num'] = Variable<int>(deviceNum);
    map['changed_at'] = Variable<DateTime>(changedAt);
    return map;
  }

  SignalIdentityChangesCompanion toCompanion(bool nullToAbsent) {
    return SignalIdentityChangesCompanion(
      id: Value(id),
      name: Value(name),
      deviceNum: Value(deviceNum),
      changedAt: Value(changedAt),
    );
  }

  factory SignalIdentityChange.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalIdentityChange(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      deviceNum: serializer.fromJson<int>(json['deviceNum']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'deviceNum': serializer.toJson<int>(deviceNum),
      'changedAt': serializer.toJson<DateTime>(changedAt),
    };
  }

  SignalIdentityChange copyWith({
    int? id,
    String? name,
    int? deviceNum,
    DateTime? changedAt,
  }) => SignalIdentityChange(
    id: id ?? this.id,
    name: name ?? this.name,
    deviceNum: deviceNum ?? this.deviceNum,
    changedAt: changedAt ?? this.changedAt,
  );
  SignalIdentityChange copyWithCompanion(SignalIdentityChangesCompanion data) {
    return SignalIdentityChange(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      deviceNum: data.deviceNum.present ? data.deviceNum.value : this.deviceNum,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalIdentityChange(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('deviceNum: $deviceNum, ')
          ..write('changedAt: $changedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, deviceNum, changedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalIdentityChange &&
          other.id == this.id &&
          other.name == this.name &&
          other.deviceNum == this.deviceNum &&
          other.changedAt == this.changedAt);
}

class SignalIdentityChangesCompanion
    extends UpdateCompanion<SignalIdentityChange> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> deviceNum;
  final Value<DateTime> changedAt;
  const SignalIdentityChangesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.deviceNum = const Value.absent(),
    this.changedAt = const Value.absent(),
  });
  SignalIdentityChangesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required int deviceNum,
    this.changedAt = const Value.absent(),
  }) : name = Value(name),
       deviceNum = Value(deviceNum);
  static Insertable<SignalIdentityChange> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? deviceNum,
    Expression<DateTime>? changedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (deviceNum != null) 'device_num': deviceNum,
      if (changedAt != null) 'changed_at': changedAt,
    });
  }

  SignalIdentityChangesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? deviceNum,
    Value<DateTime>? changedAt,
  }) {
    return SignalIdentityChangesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceNum: deviceNum ?? this.deviceNum,
      changedAt: changedAt ?? this.changedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (deviceNum.present) {
      map['device_num'] = Variable<int>(deviceNum.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalIdentityChangesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('deviceNum: $deviceNum, ')
          ..write('changedAt: $changedAt')
          ..write(')'))
        .toString();
  }
}

class $SignalMetaTable extends SignalMeta
    with TableInfo<$SignalMetaTable, SignalMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SignalMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'signal_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SignalMetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SignalMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SignalMetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SignalMetaTable createAlias(String alias) {
    return $SignalMetaTable(attachedDatabase, alias);
  }
}

class SignalMetaData extends DataClass implements Insertable<SignalMetaData> {
  final String key;
  final String value;
  const SignalMetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SignalMetaCompanion toCompanion(bool nullToAbsent) {
    return SignalMetaCompanion(key: Value(key), value: Value(value));
  }

  factory SignalMetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SignalMetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SignalMetaData copyWith({String? key, String? value}) =>
      SignalMetaData(key: key ?? this.key, value: value ?? this.value);
  SignalMetaData copyWithCompanion(SignalMetaCompanion data) {
    return SignalMetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SignalMetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignalMetaData &&
          other.key == this.key &&
          other.value == this.value);
}

class SignalMetaCompanion extends UpdateCompanion<SignalMetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SignalMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SignalMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SignalMetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SignalMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SignalMetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SignalMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta(
    'senderId',
  );
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToMessageIdMeta = const VerificationMeta(
    'replyToMessageId',
  );
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
    'reply_to_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> deliveredAt = GeneratedColumn<DateTime>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
    'read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    senderId,
    body,
    replyToMessageId,
    createdAt,
    deliveredAt,
    readAt,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
        _replyToMessageIdMeta,
        replyToMessageId.isAcceptableOrUnknown(
          data['reply_to_message_id']!,
          _replyToMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('read_at')) {
      context.handle(
        _readAtMeta,
        readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      replyToMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_message_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}delivered_at'],
      ),
      readAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}read_at'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final String id;
  final String senderId;
  final String? body;
  final String? replyToMessageId;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String status;
  const ChatMessage({
    required this.id,
    required this.senderId,
    this.body,
    this.replyToMessageId,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sender_id'] = Variable<String>(senderId);
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt);
    }
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      senderId: Value(senderId),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      createdAt: Value(createdAt),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      readAt: readAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readAt),
      status: Value(status),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<String>(json['id']),
      senderId: serializer.fromJson<String>(json['senderId']),
      body: serializer.fromJson<String?>(json['body']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deliveredAt: serializer.fromJson<DateTime?>(json['deliveredAt']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'senderId': serializer.toJson<String>(senderId),
      'body': serializer.toJson<String?>(body),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deliveredAt': serializer.toJson<DateTime?>(deliveredAt),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'status': serializer.toJson<String>(status),
    };
  }

  ChatMessage copyWith({
    String? id,
    String? senderId,
    Value<String?> body = const Value.absent(),
    Value<String?> replyToMessageId = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> deliveredAt = const Value.absent(),
    Value<DateTime?> readAt = const Value.absent(),
    String? status,
  }) => ChatMessage(
    id: id ?? this.id,
    senderId: senderId ?? this.senderId,
    body: body.present ? body.value : this.body,
    replyToMessageId: replyToMessageId.present
        ? replyToMessageId.value
        : this.replyToMessageId,
    createdAt: createdAt ?? this.createdAt,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    readAt: readAt.present ? readAt.value : this.readAt,
    status: status ?? this.status,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      body: data.body.present ? data.body.value : this.body,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('senderId: $senderId, ')
          ..write('body: $body, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    senderId,
    body,
    replyToMessageId,
    createdAt,
    deliveredAt,
    readAt,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.senderId == this.senderId &&
          other.body == this.body &&
          other.replyToMessageId == this.replyToMessageId &&
          other.createdAt == this.createdAt &&
          other.deliveredAt == this.deliveredAt &&
          other.readAt == this.readAt &&
          other.status == this.status);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<String> id;
  final Value<String> senderId;
  final Value<String?> body;
  final Value<String?> replyToMessageId;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deliveredAt;
  final Value<DateTime?> readAt;
  final Value<String> status;
  final Value<int> rowid;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.senderId = const Value.absent(),
    this.body = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    required String id,
    required String senderId,
    this.body = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    required DateTime createdAt,
    this.deliveredAt = const Value.absent(),
    this.readAt = const Value.absent(),
    required String status,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       senderId = Value(senderId),
       createdAt = Value(createdAt),
       status = Value(status);
  static Insertable<ChatMessage> custom({
    Expression<String>? id,
    Expression<String>? senderId,
    Expression<String>? body,
    Expression<String>? replyToMessageId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deliveredAt,
    Expression<DateTime>? readAt,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (senderId != null) 'sender_id': senderId,
      if (body != null) 'body': body,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (createdAt != null) 'created_at': createdAt,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (readAt != null) 'read_at': readAt,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? senderId,
    Value<String?>? body,
    Value<String?>? replyToMessageId,
    Value<DateTime>? createdAt,
    Value<DateTime?>? deliveredAt,
    Value<DateTime?>? readAt,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      body: body ?? this.body,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      readAt: readAt ?? this.readAt,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<DateTime>(deliveredAt.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('senderId: $senderId, ')
          ..write('body: $body, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('createdAt: $createdAt, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('readAt: $readAt, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatReactionsTable extends ChatReactions
    with TableInfo<$ChatReactionsTable, ChatReaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatReactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reactorIdMeta = const VerificationMeta(
    'reactorId',
  );
  @override
  late final GeneratedColumn<String> reactorId = GeneratedColumn<String>(
    'reactor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emojiMeta = const VerificationMeta('emoji');
  @override
  late final GeneratedColumn<String> emoji = GeneratedColumn<String>(
    'emoji',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    reactorId,
    emoji,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_reactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatReaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('reactor_id')) {
      context.handle(
        _reactorIdMeta,
        reactorId.isAcceptableOrUnknown(data['reactor_id']!, _reactorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_reactorIdMeta);
    }
    if (data.containsKey('emoji')) {
      context.handle(
        _emojiMeta,
        emoji.isAcceptableOrUnknown(data['emoji']!, _emojiMeta),
      );
    } else if (isInserting) {
      context.missing(_emojiMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId, reactorId, emoji};
  @override
  ChatReaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatReaction(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      reactorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reactor_id'],
      )!,
      emoji: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}emoji'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatReactionsTable createAlias(String alias) {
    return $ChatReactionsTable(attachedDatabase, alias);
  }
}

class ChatReaction extends DataClass implements Insertable<ChatReaction> {
  final String messageId;
  final String reactorId;
  final String emoji;
  final DateTime createdAt;
  const ChatReaction({
    required this.messageId,
    required this.reactorId,
    required this.emoji,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['reactor_id'] = Variable<String>(reactorId);
    map['emoji'] = Variable<String>(emoji);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ChatReactionsCompanion toCompanion(bool nullToAbsent) {
    return ChatReactionsCompanion(
      messageId: Value(messageId),
      reactorId: Value(reactorId),
      emoji: Value(emoji),
      createdAt: Value(createdAt),
    );
  }

  factory ChatReaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatReaction(
      messageId: serializer.fromJson<String>(json['messageId']),
      reactorId: serializer.fromJson<String>(json['reactorId']),
      emoji: serializer.fromJson<String>(json['emoji']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'reactorId': serializer.toJson<String>(reactorId),
      'emoji': serializer.toJson<String>(emoji),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ChatReaction copyWith({
    String? messageId,
    String? reactorId,
    String? emoji,
    DateTime? createdAt,
  }) => ChatReaction(
    messageId: messageId ?? this.messageId,
    reactorId: reactorId ?? this.reactorId,
    emoji: emoji ?? this.emoji,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatReaction copyWithCompanion(ChatReactionsCompanion data) {
    return ChatReaction(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      reactorId: data.reactorId.present ? data.reactorId.value : this.reactorId,
      emoji: data.emoji.present ? data.emoji.value : this.emoji,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatReaction(')
          ..write('messageId: $messageId, ')
          ..write('reactorId: $reactorId, ')
          ..write('emoji: $emoji, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(messageId, reactorId, emoji, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatReaction &&
          other.messageId == this.messageId &&
          other.reactorId == this.reactorId &&
          other.emoji == this.emoji &&
          other.createdAt == this.createdAt);
}

class ChatReactionsCompanion extends UpdateCompanion<ChatReaction> {
  final Value<String> messageId;
  final Value<String> reactorId;
  final Value<String> emoji;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ChatReactionsCompanion({
    this.messageId = const Value.absent(),
    this.reactorId = const Value.absent(),
    this.emoji = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatReactionsCompanion.insert({
    required String messageId,
    required String reactorId,
    required String emoji,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       reactorId = Value(reactorId),
       emoji = Value(emoji),
       createdAt = Value(createdAt);
  static Insertable<ChatReaction> custom({
    Expression<String>? messageId,
    Expression<String>? reactorId,
    Expression<String>? emoji,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (reactorId != null) 'reactor_id': reactorId,
      if (emoji != null) 'emoji': emoji,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatReactionsCompanion copyWith({
    Value<String>? messageId,
    Value<String>? reactorId,
    Value<String>? emoji,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ChatReactionsCompanion(
      messageId: messageId ?? this.messageId,
      reactorId: reactorId ?? this.reactorId,
      emoji: emoji ?? this.emoji,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (reactorId.present) {
      map['reactor_id'] = Variable<String>(reactorId.value);
    }
    if (emoji.present) {
      map['emoji'] = Variable<String>(emoji.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatReactionsCompanion(')
          ..write('messageId: $messageId, ')
          ..write('reactorId: $reactorId, ')
          ..write('emoji: $emoji, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SignalDb extends GeneratedDatabase {
  _$SignalDb(QueryExecutor e) : super(e);
  $SignalDbManager get managers => $SignalDbManager(this);
  late final $SignalSessionsTable signalSessions = $SignalSessionsTable(this);
  late final $SignalPrekeysTable signalPrekeys = $SignalPrekeysTable(this);
  late final $SignalSignedPrekeysTable signalSignedPrekeys =
      $SignalSignedPrekeysTable(this);
  late final $SignalIdentitiesTable signalIdentities = $SignalIdentitiesTable(
    this,
  );
  late final $SignalIdentityChangesTable signalIdentityChanges =
      $SignalIdentityChangesTable(this);
  late final $SignalMetaTable signalMeta = $SignalMetaTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $ChatReactionsTable chatReactions = $ChatReactionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    signalSessions,
    signalPrekeys,
    signalSignedPrekeys,
    signalIdentities,
    signalIdentityChanges,
    signalMeta,
    chatMessages,
    chatReactions,
  ];
}

typedef $$SignalSessionsTableCreateCompanionBuilder =
    SignalSessionsCompanion Function({
      required String name,
      required int deviceNum,
      required Uint8List record,
      Value<int> rowid,
    });
typedef $$SignalSessionsTableUpdateCompanionBuilder =
    SignalSessionsCompanion Function({
      Value<String> name,
      Value<int> deviceNum,
      Value<Uint8List> record,
      Value<int> rowid,
    });

class $$SignalSessionsTableFilterComposer
    extends Composer<_$SignalDb, $SignalSessionsTable> {
  $$SignalSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceNum => $composableBuilder(
    column: $table.deviceNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalSessionsTableOrderingComposer
    extends Composer<_$SignalDb, $SignalSessionsTable> {
  $$SignalSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceNum => $composableBuilder(
    column: $table.deviceNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalSessionsTableAnnotationComposer
    extends Composer<_$SignalDb, $SignalSessionsTable> {
  $$SignalSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get deviceNum =>
      $composableBuilder(column: $table.deviceNum, builder: (column) => column);

  GeneratedColumn<Uint8List> get record =>
      $composableBuilder(column: $table.record, builder: (column) => column);
}

class $$SignalSessionsTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $SignalSessionsTable,
          SignalSession,
          $$SignalSessionsTableFilterComposer,
          $$SignalSessionsTableOrderingComposer,
          $$SignalSessionsTableAnnotationComposer,
          $$SignalSessionsTableCreateCompanionBuilder,
          $$SignalSessionsTableUpdateCompanionBuilder,
          (
            SignalSession,
            BaseReferences<_$SignalDb, $SignalSessionsTable, SignalSession>,
          ),
          SignalSession,
          PrefetchHooks Function()
        > {
  $$SignalSessionsTableTableManager(_$SignalDb db, $SignalSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignalSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<int> deviceNum = const Value.absent(),
                Value<Uint8List> record = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignalSessionsCompanion(
                name: name,
                deviceNum: deviceNum,
                record: record,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                required int deviceNum,
                required Uint8List record,
                Value<int> rowid = const Value.absent(),
              }) => SignalSessionsCompanion.insert(
                name: name,
                deviceNum: deviceNum,
                record: record,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $SignalSessionsTable,
      SignalSession,
      $$SignalSessionsTableFilterComposer,
      $$SignalSessionsTableOrderingComposer,
      $$SignalSessionsTableAnnotationComposer,
      $$SignalSessionsTableCreateCompanionBuilder,
      $$SignalSessionsTableUpdateCompanionBuilder,
      (
        SignalSession,
        BaseReferences<_$SignalDb, $SignalSessionsTable, SignalSession>,
      ),
      SignalSession,
      PrefetchHooks Function()
    >;
typedef $$SignalPrekeysTableCreateCompanionBuilder =
    SignalPrekeysCompanion Function({
      Value<int> prekeyId,
      required Uint8List record,
    });
typedef $$SignalPrekeysTableUpdateCompanionBuilder =
    SignalPrekeysCompanion Function({
      Value<int> prekeyId,
      Value<Uint8List> record,
    });

class $$SignalPrekeysTableFilterComposer
    extends Composer<_$SignalDb, $SignalPrekeysTable> {
  $$SignalPrekeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get prekeyId => $composableBuilder(
    column: $table.prekeyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalPrekeysTableOrderingComposer
    extends Composer<_$SignalDb, $SignalPrekeysTable> {
  $$SignalPrekeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get prekeyId => $composableBuilder(
    column: $table.prekeyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalPrekeysTableAnnotationComposer
    extends Composer<_$SignalDb, $SignalPrekeysTable> {
  $$SignalPrekeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get prekeyId =>
      $composableBuilder(column: $table.prekeyId, builder: (column) => column);

  GeneratedColumn<Uint8List> get record =>
      $composableBuilder(column: $table.record, builder: (column) => column);
}

class $$SignalPrekeysTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $SignalPrekeysTable,
          SignalPrekey,
          $$SignalPrekeysTableFilterComposer,
          $$SignalPrekeysTableOrderingComposer,
          $$SignalPrekeysTableAnnotationComposer,
          $$SignalPrekeysTableCreateCompanionBuilder,
          $$SignalPrekeysTableUpdateCompanionBuilder,
          (
            SignalPrekey,
            BaseReferences<_$SignalDb, $SignalPrekeysTable, SignalPrekey>,
          ),
          SignalPrekey,
          PrefetchHooks Function()
        > {
  $$SignalPrekeysTableTableManager(_$SignalDb db, $SignalPrekeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalPrekeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalPrekeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignalPrekeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> prekeyId = const Value.absent(),
                Value<Uint8List> record = const Value.absent(),
              }) => SignalPrekeysCompanion(prekeyId: prekeyId, record: record),
          createCompanionCallback:
              ({
                Value<int> prekeyId = const Value.absent(),
                required Uint8List record,
              }) => SignalPrekeysCompanion.insert(
                prekeyId: prekeyId,
                record: record,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalPrekeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $SignalPrekeysTable,
      SignalPrekey,
      $$SignalPrekeysTableFilterComposer,
      $$SignalPrekeysTableOrderingComposer,
      $$SignalPrekeysTableAnnotationComposer,
      $$SignalPrekeysTableCreateCompanionBuilder,
      $$SignalPrekeysTableUpdateCompanionBuilder,
      (
        SignalPrekey,
        BaseReferences<_$SignalDb, $SignalPrekeysTable, SignalPrekey>,
      ),
      SignalPrekey,
      PrefetchHooks Function()
    >;
typedef $$SignalSignedPrekeysTableCreateCompanionBuilder =
    SignalSignedPrekeysCompanion Function({
      Value<int> signedPrekeyId,
      required Uint8List record,
    });
typedef $$SignalSignedPrekeysTableUpdateCompanionBuilder =
    SignalSignedPrekeysCompanion Function({
      Value<int> signedPrekeyId,
      Value<Uint8List> record,
    });

class $$SignalSignedPrekeysTableFilterComposer
    extends Composer<_$SignalDb, $SignalSignedPrekeysTable> {
  $$SignalSignedPrekeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get signedPrekeyId => $composableBuilder(
    column: $table.signedPrekeyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalSignedPrekeysTableOrderingComposer
    extends Composer<_$SignalDb, $SignalSignedPrekeysTable> {
  $$SignalSignedPrekeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get signedPrekeyId => $composableBuilder(
    column: $table.signedPrekeyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get record => $composableBuilder(
    column: $table.record,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalSignedPrekeysTableAnnotationComposer
    extends Composer<_$SignalDb, $SignalSignedPrekeysTable> {
  $$SignalSignedPrekeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get signedPrekeyId => $composableBuilder(
    column: $table.signedPrekeyId,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get record =>
      $composableBuilder(column: $table.record, builder: (column) => column);
}

class $$SignalSignedPrekeysTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $SignalSignedPrekeysTable,
          SignalSignedPrekey,
          $$SignalSignedPrekeysTableFilterComposer,
          $$SignalSignedPrekeysTableOrderingComposer,
          $$SignalSignedPrekeysTableAnnotationComposer,
          $$SignalSignedPrekeysTableCreateCompanionBuilder,
          $$SignalSignedPrekeysTableUpdateCompanionBuilder,
          (
            SignalSignedPrekey,
            BaseReferences<
              _$SignalDb,
              $SignalSignedPrekeysTable,
              SignalSignedPrekey
            >,
          ),
          SignalSignedPrekey,
          PrefetchHooks Function()
        > {
  $$SignalSignedPrekeysTableTableManager(
    _$SignalDb db,
    $SignalSignedPrekeysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalSignedPrekeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalSignedPrekeysTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SignalSignedPrekeysTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> signedPrekeyId = const Value.absent(),
                Value<Uint8List> record = const Value.absent(),
              }) => SignalSignedPrekeysCompanion(
                signedPrekeyId: signedPrekeyId,
                record: record,
              ),
          createCompanionCallback:
              ({
                Value<int> signedPrekeyId = const Value.absent(),
                required Uint8List record,
              }) => SignalSignedPrekeysCompanion.insert(
                signedPrekeyId: signedPrekeyId,
                record: record,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalSignedPrekeysTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $SignalSignedPrekeysTable,
      SignalSignedPrekey,
      $$SignalSignedPrekeysTableFilterComposer,
      $$SignalSignedPrekeysTableOrderingComposer,
      $$SignalSignedPrekeysTableAnnotationComposer,
      $$SignalSignedPrekeysTableCreateCompanionBuilder,
      $$SignalSignedPrekeysTableUpdateCompanionBuilder,
      (
        SignalSignedPrekey,
        BaseReferences<
          _$SignalDb,
          $SignalSignedPrekeysTable,
          SignalSignedPrekey
        >,
      ),
      SignalSignedPrekey,
      PrefetchHooks Function()
    >;
typedef $$SignalIdentitiesTableCreateCompanionBuilder =
    SignalIdentitiesCompanion Function({
      required String name,
      required int deviceNum,
      required Uint8List identityKey,
      Value<DateTime> firstSeen,
      Value<int> rowid,
    });
typedef $$SignalIdentitiesTableUpdateCompanionBuilder =
    SignalIdentitiesCompanion Function({
      Value<String> name,
      Value<int> deviceNum,
      Value<Uint8List> identityKey,
      Value<DateTime> firstSeen,
      Value<int> rowid,
    });

class $$SignalIdentitiesTableFilterComposer
    extends Composer<_$SignalDb, $SignalIdentitiesTable> {
  $$SignalIdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceNum => $composableBuilder(
    column: $table.deviceNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalIdentitiesTableOrderingComposer
    extends Composer<_$SignalDb, $SignalIdentitiesTable> {
  $$SignalIdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceNum => $composableBuilder(
    column: $table.deviceNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalIdentitiesTableAnnotationComposer
    extends Composer<_$SignalDb, $SignalIdentitiesTable> {
  $$SignalIdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get deviceNum =>
      $composableBuilder(column: $table.deviceNum, builder: (column) => column);

  GeneratedColumn<Uint8List> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);
}

class $$SignalIdentitiesTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $SignalIdentitiesTable,
          SignalIdentity,
          $$SignalIdentitiesTableFilterComposer,
          $$SignalIdentitiesTableOrderingComposer,
          $$SignalIdentitiesTableAnnotationComposer,
          $$SignalIdentitiesTableCreateCompanionBuilder,
          $$SignalIdentitiesTableUpdateCompanionBuilder,
          (
            SignalIdentity,
            BaseReferences<_$SignalDb, $SignalIdentitiesTable, SignalIdentity>,
          ),
          SignalIdentity,
          PrefetchHooks Function()
        > {
  $$SignalIdentitiesTableTableManager(
    _$SignalDb db,
    $SignalIdentitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalIdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalIdentitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignalIdentitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<int> deviceNum = const Value.absent(),
                Value<Uint8List> identityKey = const Value.absent(),
                Value<DateTime> firstSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignalIdentitiesCompanion(
                name: name,
                deviceNum: deviceNum,
                identityKey: identityKey,
                firstSeen: firstSeen,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                required int deviceNum,
                required Uint8List identityKey,
                Value<DateTime> firstSeen = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignalIdentitiesCompanion.insert(
                name: name,
                deviceNum: deviceNum,
                identityKey: identityKey,
                firstSeen: firstSeen,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalIdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $SignalIdentitiesTable,
      SignalIdentity,
      $$SignalIdentitiesTableFilterComposer,
      $$SignalIdentitiesTableOrderingComposer,
      $$SignalIdentitiesTableAnnotationComposer,
      $$SignalIdentitiesTableCreateCompanionBuilder,
      $$SignalIdentitiesTableUpdateCompanionBuilder,
      (
        SignalIdentity,
        BaseReferences<_$SignalDb, $SignalIdentitiesTable, SignalIdentity>,
      ),
      SignalIdentity,
      PrefetchHooks Function()
    >;
typedef $$SignalIdentityChangesTableCreateCompanionBuilder =
    SignalIdentityChangesCompanion Function({
      Value<int> id,
      required String name,
      required int deviceNum,
      Value<DateTime> changedAt,
    });
typedef $$SignalIdentityChangesTableUpdateCompanionBuilder =
    SignalIdentityChangesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> deviceNum,
      Value<DateTime> changedAt,
    });

class $$SignalIdentityChangesTableFilterComposer
    extends Composer<_$SignalDb, $SignalIdentityChangesTable> {
  $$SignalIdentityChangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceNum => $composableBuilder(
    column: $table.deviceNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalIdentityChangesTableOrderingComposer
    extends Composer<_$SignalDb, $SignalIdentityChangesTable> {
  $$SignalIdentityChangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceNum => $composableBuilder(
    column: $table.deviceNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
    column: $table.changedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalIdentityChangesTableAnnotationComposer
    extends Composer<_$SignalDb, $SignalIdentityChangesTable> {
  $$SignalIdentityChangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get deviceNum =>
      $composableBuilder(column: $table.deviceNum, builder: (column) => column);

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);
}

class $$SignalIdentityChangesTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $SignalIdentityChangesTable,
          SignalIdentityChange,
          $$SignalIdentityChangesTableFilterComposer,
          $$SignalIdentityChangesTableOrderingComposer,
          $$SignalIdentityChangesTableAnnotationComposer,
          $$SignalIdentityChangesTableCreateCompanionBuilder,
          $$SignalIdentityChangesTableUpdateCompanionBuilder,
          (
            SignalIdentityChange,
            BaseReferences<
              _$SignalDb,
              $SignalIdentityChangesTable,
              SignalIdentityChange
            >,
          ),
          SignalIdentityChange,
          PrefetchHooks Function()
        > {
  $$SignalIdentityChangesTableTableManager(
    _$SignalDb db,
    $SignalIdentityChangesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalIdentityChangesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SignalIdentityChangesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SignalIdentityChangesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> deviceNum = const Value.absent(),
                Value<DateTime> changedAt = const Value.absent(),
              }) => SignalIdentityChangesCompanion(
                id: id,
                name: name,
                deviceNum: deviceNum,
                changedAt: changedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required int deviceNum,
                Value<DateTime> changedAt = const Value.absent(),
              }) => SignalIdentityChangesCompanion.insert(
                id: id,
                name: name,
                deviceNum: deviceNum,
                changedAt: changedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalIdentityChangesTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $SignalIdentityChangesTable,
      SignalIdentityChange,
      $$SignalIdentityChangesTableFilterComposer,
      $$SignalIdentityChangesTableOrderingComposer,
      $$SignalIdentityChangesTableAnnotationComposer,
      $$SignalIdentityChangesTableCreateCompanionBuilder,
      $$SignalIdentityChangesTableUpdateCompanionBuilder,
      (
        SignalIdentityChange,
        BaseReferences<
          _$SignalDb,
          $SignalIdentityChangesTable,
          SignalIdentityChange
        >,
      ),
      SignalIdentityChange,
      PrefetchHooks Function()
    >;
typedef $$SignalMetaTableCreateCompanionBuilder =
    SignalMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SignalMetaTableUpdateCompanionBuilder =
    SignalMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SignalMetaTableFilterComposer
    extends Composer<_$SignalDb, $SignalMetaTable> {
  $$SignalMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SignalMetaTableOrderingComposer
    extends Composer<_$SignalDb, $SignalMetaTable> {
  $$SignalMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SignalMetaTableAnnotationComposer
    extends Composer<_$SignalDb, $SignalMetaTable> {
  $$SignalMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SignalMetaTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $SignalMetaTable,
          SignalMetaData,
          $$SignalMetaTableFilterComposer,
          $$SignalMetaTableOrderingComposer,
          $$SignalMetaTableAnnotationComposer,
          $$SignalMetaTableCreateCompanionBuilder,
          $$SignalMetaTableUpdateCompanionBuilder,
          (
            SignalMetaData,
            BaseReferences<_$SignalDb, $SignalMetaTable, SignalMetaData>,
          ),
          SignalMetaData,
          PrefetchHooks Function()
        > {
  $$SignalMetaTableTableManager(_$SignalDb db, $SignalMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SignalMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SignalMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SignalMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SignalMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SignalMetaCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SignalMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $SignalMetaTable,
      SignalMetaData,
      $$SignalMetaTableFilterComposer,
      $$SignalMetaTableOrderingComposer,
      $$SignalMetaTableAnnotationComposer,
      $$SignalMetaTableCreateCompanionBuilder,
      $$SignalMetaTableUpdateCompanionBuilder,
      (
        SignalMetaData,
        BaseReferences<_$SignalDb, $SignalMetaTable, SignalMetaData>,
      ),
      SignalMetaData,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      required String id,
      required String senderId,
      Value<String?> body,
      Value<String?> replyToMessageId,
      required DateTime createdAt,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      required String status,
      Value<int> rowid,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<String> id,
      Value<String> senderId,
      Value<String?> body,
      Value<String?> replyToMessageId,
      Value<DateTime> createdAt,
      Value<DateTime?> deliveredAt,
      Value<DateTime?> readAt,
      Value<String> status,
      Value<int> rowid,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$SignalDb, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$SignalDb, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId => $composableBuilder(
    column: $table.senderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
    column: $table.readAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$SignalDb, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessage,
            BaseReferences<_$SignalDb, $ChatMessagesTable, ChatMessage>,
          ),
          ChatMessage,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$SignalDb db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                senderId: senderId,
                body: body,
                replyToMessageId: replyToMessageId,
                createdAt: createdAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String senderId,
                Value<String?> body = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> deliveredAt = const Value.absent(),
                Value<DateTime?> readAt = const Value.absent(),
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                senderId: senderId,
                body: body,
                replyToMessageId: replyToMessageId,
                createdAt: createdAt,
                deliveredAt: deliveredAt,
                readAt: readAt,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessage,
        BaseReferences<_$SignalDb, $ChatMessagesTable, ChatMessage>,
      ),
      ChatMessage,
      PrefetchHooks Function()
    >;
typedef $$ChatReactionsTableCreateCompanionBuilder =
    ChatReactionsCompanion Function({
      required String messageId,
      required String reactorId,
      required String emoji,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ChatReactionsTableUpdateCompanionBuilder =
    ChatReactionsCompanion Function({
      Value<String> messageId,
      Value<String> reactorId,
      Value<String> emoji,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ChatReactionsTableFilterComposer
    extends Composer<_$SignalDb, $ChatReactionsTable> {
  $$ChatReactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reactorId => $composableBuilder(
    column: $table.reactorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatReactionsTableOrderingComposer
    extends Composer<_$SignalDb, $ChatReactionsTable> {
  $$ChatReactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reactorId => $composableBuilder(
    column: $table.reactorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get emoji => $composableBuilder(
    column: $table.emoji,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatReactionsTableAnnotationComposer
    extends Composer<_$SignalDb, $ChatReactionsTable> {
  $$ChatReactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get reactorId =>
      $composableBuilder(column: $table.reactorId, builder: (column) => column);

  GeneratedColumn<String> get emoji =>
      $composableBuilder(column: $table.emoji, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ChatReactionsTableTableManager
    extends
        RootTableManager<
          _$SignalDb,
          $ChatReactionsTable,
          ChatReaction,
          $$ChatReactionsTableFilterComposer,
          $$ChatReactionsTableOrderingComposer,
          $$ChatReactionsTableAnnotationComposer,
          $$ChatReactionsTableCreateCompanionBuilder,
          $$ChatReactionsTableUpdateCompanionBuilder,
          (
            ChatReaction,
            BaseReferences<_$SignalDb, $ChatReactionsTable, ChatReaction>,
          ),
          ChatReaction,
          PrefetchHooks Function()
        > {
  $$ChatReactionsTableTableManager(_$SignalDb db, $ChatReactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatReactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatReactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatReactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<String> reactorId = const Value.absent(),
                Value<String> emoji = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatReactionsCompanion(
                messageId: messageId,
                reactorId: reactorId,
                emoji: emoji,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required String reactorId,
                required String emoji,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ChatReactionsCompanion.insert(
                messageId: messageId,
                reactorId: reactorId,
                emoji: emoji,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatReactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SignalDb,
      $ChatReactionsTable,
      ChatReaction,
      $$ChatReactionsTableFilterComposer,
      $$ChatReactionsTableOrderingComposer,
      $$ChatReactionsTableAnnotationComposer,
      $$ChatReactionsTableCreateCompanionBuilder,
      $$ChatReactionsTableUpdateCompanionBuilder,
      (
        ChatReaction,
        BaseReferences<_$SignalDb, $ChatReactionsTable, ChatReaction>,
      ),
      ChatReaction,
      PrefetchHooks Function()
    >;

class $SignalDbManager {
  final _$SignalDb _db;
  $SignalDbManager(this._db);
  $$SignalSessionsTableTableManager get signalSessions =>
      $$SignalSessionsTableTableManager(_db, _db.signalSessions);
  $$SignalPrekeysTableTableManager get signalPrekeys =>
      $$SignalPrekeysTableTableManager(_db, _db.signalPrekeys);
  $$SignalSignedPrekeysTableTableManager get signalSignedPrekeys =>
      $$SignalSignedPrekeysTableTableManager(_db, _db.signalSignedPrekeys);
  $$SignalIdentitiesTableTableManager get signalIdentities =>
      $$SignalIdentitiesTableTableManager(_db, _db.signalIdentities);
  $$SignalIdentityChangesTableTableManager get signalIdentityChanges =>
      $$SignalIdentityChangesTableTableManager(_db, _db.signalIdentityChanges);
  $$SignalMetaTableTableManager get signalMeta =>
      $$SignalMetaTableTableManager(_db, _db.signalMeta);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$ChatReactionsTableTableManager get chatReactions =>
      $$ChatReactionsTableTableManager(_db, _db.chatReactions);
}
