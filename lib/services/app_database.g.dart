// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MahsaServersTable extends MahsaServers
    with TableInfo<$MahsaServersTable, MahsaServer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MahsaServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _rawLinkMeta =
      const VerificationMeta('rawLink');
  @override
  late final GeneratedColumn<String> rawLink = GeneratedColumn<String>(
      'raw_link', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _savedAtMeta =
      const VerificationMeta('savedAt');
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
      'saved_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updateIntervalHoursMeta =
      const VerificationMeta('updateIntervalHours');
  @override
  late final GeneratedColumn<int> updateIntervalHours = GeneratedColumn<int>(
      'update_interval_hours', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(6));
  @override
  List<GeneratedColumn> get $columns =>
      [id, rawLink, savedAt, updateIntervalHours];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mahsa_servers';
  @override
  VerificationContext validateIntegrity(Insertable<MahsaServer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('raw_link')) {
      context.handle(_rawLinkMeta,
          rawLink.isAcceptableOrUnknown(data['raw_link']!, _rawLinkMeta));
    } else if (isInserting) {
      context.missing(_rawLinkMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(_savedAtMeta,
          savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta));
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('update_interval_hours')) {
      context.handle(
          _updateIntervalHoursMeta,
          updateIntervalHours.isAcceptableOrUnknown(
              data['update_interval_hours']!, _updateIntervalHoursMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MahsaServer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MahsaServer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      rawLink: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}raw_link'])!,
      savedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}saved_at'])!,
      updateIntervalHours: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}update_interval_hours'])!,
    );
  }

  @override
  $MahsaServersTable createAlias(String alias) {
    return $MahsaServersTable(attachedDatabase, alias);
  }
}

class MahsaServer extends DataClass implements Insertable<MahsaServer> {
  final int id;
  final String rawLink;
  final DateTime savedAt;
  final int updateIntervalHours;
  const MahsaServer(
      {required this.id,
      required this.rawLink,
      required this.savedAt,
      required this.updateIntervalHours});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['raw_link'] = Variable<String>(rawLink);
    map['saved_at'] = Variable<DateTime>(savedAt);
    map['update_interval_hours'] = Variable<int>(updateIntervalHours);
    return map;
  }

  MahsaServersCompanion toCompanion(bool nullToAbsent) {
    return MahsaServersCompanion(
      id: Value(id),
      rawLink: Value(rawLink),
      savedAt: Value(savedAt),
      updateIntervalHours: Value(updateIntervalHours),
    );
  }

  factory MahsaServer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MahsaServer(
      id: serializer.fromJson<int>(json['id']),
      rawLink: serializer.fromJson<String>(json['rawLink']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
      updateIntervalHours:
          serializer.fromJson<int>(json['updateIntervalHours']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rawLink': serializer.toJson<String>(rawLink),
      'savedAt': serializer.toJson<DateTime>(savedAt),
      'updateIntervalHours': serializer.toJson<int>(updateIntervalHours),
    };
  }

  MahsaServer copyWith(
          {int? id,
          String? rawLink,
          DateTime? savedAt,
          int? updateIntervalHours}) =>
      MahsaServer(
        id: id ?? this.id,
        rawLink: rawLink ?? this.rawLink,
        savedAt: savedAt ?? this.savedAt,
        updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
      );
  MahsaServer copyWithCompanion(MahsaServersCompanion data) {
    return MahsaServer(
      id: data.id.present ? data.id.value : this.id,
      rawLink: data.rawLink.present ? data.rawLink.value : this.rawLink,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      updateIntervalHours: data.updateIntervalHours.present
          ? data.updateIntervalHours.value
          : this.updateIntervalHours,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MahsaServer(')
          ..write('id: $id, ')
          ..write('rawLink: $rawLink, ')
          ..write('savedAt: $savedAt, ')
          ..write('updateIntervalHours: $updateIntervalHours')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, rawLink, savedAt, updateIntervalHours);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MahsaServer &&
          other.id == this.id &&
          other.rawLink == this.rawLink &&
          other.savedAt == this.savedAt &&
          other.updateIntervalHours == this.updateIntervalHours);
}

class MahsaServersCompanion extends UpdateCompanion<MahsaServer> {
  final Value<int> id;
  final Value<String> rawLink;
  final Value<DateTime> savedAt;
  final Value<int> updateIntervalHours;
  const MahsaServersCompanion({
    this.id = const Value.absent(),
    this.rawLink = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.updateIntervalHours = const Value.absent(),
  });
  MahsaServersCompanion.insert({
    this.id = const Value.absent(),
    required String rawLink,
    required DateTime savedAt,
    this.updateIntervalHours = const Value.absent(),
  })  : rawLink = Value(rawLink),
        savedAt = Value(savedAt);
  static Insertable<MahsaServer> custom({
    Expression<int>? id,
    Expression<String>? rawLink,
    Expression<DateTime>? savedAt,
    Expression<int>? updateIntervalHours,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rawLink != null) 'raw_link': rawLink,
      if (savedAt != null) 'saved_at': savedAt,
      if (updateIntervalHours != null)
        'update_interval_hours': updateIntervalHours,
    });
  }

  MahsaServersCompanion copyWith(
      {Value<int>? id,
      Value<String>? rawLink,
      Value<DateTime>? savedAt,
      Value<int>? updateIntervalHours}) {
    return MahsaServersCompanion(
      id: id ?? this.id,
      rawLink: rawLink ?? this.rawLink,
      savedAt: savedAt ?? this.savedAt,
      updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rawLink.present) {
      map['raw_link'] = Variable<String>(rawLink.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (updateIntervalHours.present) {
      map['update_interval_hours'] = Variable<int>(updateIntervalHours.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MahsaServersCompanion(')
          ..write('id: $id, ')
          ..write('rawLink: $rawLink, ')
          ..write('savedAt: $savedAt, ')
          ..write('updateIntervalHours: $updateIntervalHours')
          ..write(')'))
        .toString();
  }
}

class $PatternihaServersTable extends PatternihaServers
    with TableInfo<$PatternihaServersTable, PatternihaServer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PatternihaServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _rawLinkMeta =
      const VerificationMeta('rawLink');
  @override
  late final GeneratedColumn<String> rawLink = GeneratedColumn<String>(
      'raw_link', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _flagMeta = const VerificationMeta('flag');
  @override
  late final GeneratedColumn<String> flag = GeneratedColumn<String>(
      'flag', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('🌐'));
  static const VerificationMeta _countryMeta =
      const VerificationMeta('country');
  @override
  late final GeneratedColumn<String> country = GeneratedColumn<String>(
      'country', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _savedAtMeta =
      const VerificationMeta('savedAt');
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
      'saved_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updateIntervalHoursMeta =
      const VerificationMeta('updateIntervalHours');
  @override
  late final GeneratedColumn<int> updateIntervalHours = GeneratedColumn<int>(
      'update_interval_hours', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(24));
  @override
  List<GeneratedColumn> get $columns =>
      [id, rawLink, name, flag, country, savedAt, updateIntervalHours];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'patterniha_servers';
  @override
  VerificationContext validateIntegrity(Insertable<PatternihaServer> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('raw_link')) {
      context.handle(_rawLinkMeta,
          rawLink.isAcceptableOrUnknown(data['raw_link']!, _rawLinkMeta));
    } else if (isInserting) {
      context.missing(_rawLinkMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('flag')) {
      context.handle(
          _flagMeta, flag.isAcceptableOrUnknown(data['flag']!, _flagMeta));
    }
    if (data.containsKey('country')) {
      context.handle(_countryMeta,
          country.isAcceptableOrUnknown(data['country']!, _countryMeta));
    }
    if (data.containsKey('saved_at')) {
      context.handle(_savedAtMeta,
          savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta));
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    if (data.containsKey('update_interval_hours')) {
      context.handle(
          _updateIntervalHoursMeta,
          updateIntervalHours.isAcceptableOrUnknown(
              data['update_interval_hours']!, _updateIntervalHoursMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PatternihaServer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PatternihaServer(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      rawLink: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}raw_link'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      flag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}flag'])!,
      country: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}country'])!,
      savedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}saved_at'])!,
      updateIntervalHours: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}update_interval_hours'])!,
    );
  }

  @override
  $PatternihaServersTable createAlias(String alias) {
    return $PatternihaServersTable(attachedDatabase, alias);
  }
}

class PatternihaServer extends DataClass
    implements Insertable<PatternihaServer> {
  final int id;
  final String rawLink;
  final String name;
  final String flag;
  final String country;
  final DateTime savedAt;
  final int updateIntervalHours;
  const PatternihaServer(
      {required this.id,
      required this.rawLink,
      required this.name,
      required this.flag,
      required this.country,
      required this.savedAt,
      required this.updateIntervalHours});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['raw_link'] = Variable<String>(rawLink);
    map['name'] = Variable<String>(name);
    map['flag'] = Variable<String>(flag);
    map['country'] = Variable<String>(country);
    map['saved_at'] = Variable<DateTime>(savedAt);
    map['update_interval_hours'] = Variable<int>(updateIntervalHours);
    return map;
  }

  PatternihaServersCompanion toCompanion(bool nullToAbsent) {
    return PatternihaServersCompanion(
      id: Value(id),
      rawLink: Value(rawLink),
      name: Value(name),
      flag: Value(flag),
      country: Value(country),
      savedAt: Value(savedAt),
      updateIntervalHours: Value(updateIntervalHours),
    );
  }

  factory PatternihaServer.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PatternihaServer(
      id: serializer.fromJson<int>(json['id']),
      rawLink: serializer.fromJson<String>(json['rawLink']),
      name: serializer.fromJson<String>(json['name']),
      flag: serializer.fromJson<String>(json['flag']),
      country: serializer.fromJson<String>(json['country']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
      updateIntervalHours:
          serializer.fromJson<int>(json['updateIntervalHours']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'rawLink': serializer.toJson<String>(rawLink),
      'name': serializer.toJson<String>(name),
      'flag': serializer.toJson<String>(flag),
      'country': serializer.toJson<String>(country),
      'savedAt': serializer.toJson<DateTime>(savedAt),
      'updateIntervalHours': serializer.toJson<int>(updateIntervalHours),
    };
  }

  PatternihaServer copyWith(
          {int? id,
          String? rawLink,
          String? name,
          String? flag,
          String? country,
          DateTime? savedAt,
          int? updateIntervalHours}) =>
      PatternihaServer(
        id: id ?? this.id,
        rawLink: rawLink ?? this.rawLink,
        name: name ?? this.name,
        flag: flag ?? this.flag,
        country: country ?? this.country,
        savedAt: savedAt ?? this.savedAt,
        updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
      );
  PatternihaServer copyWithCompanion(PatternihaServersCompanion data) {
    return PatternihaServer(
      id: data.id.present ? data.id.value : this.id,
      rawLink: data.rawLink.present ? data.rawLink.value : this.rawLink,
      name: data.name.present ? data.name.value : this.name,
      flag: data.flag.present ? data.flag.value : this.flag,
      country: data.country.present ? data.country.value : this.country,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
      updateIntervalHours: data.updateIntervalHours.present
          ? data.updateIntervalHours.value
          : this.updateIntervalHours,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PatternihaServer(')
          ..write('id: $id, ')
          ..write('rawLink: $rawLink, ')
          ..write('name: $name, ')
          ..write('flag: $flag, ')
          ..write('country: $country, ')
          ..write('savedAt: $savedAt, ')
          ..write('updateIntervalHours: $updateIntervalHours')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, rawLink, name, flag, country, savedAt, updateIntervalHours);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PatternihaServer &&
          other.id == this.id &&
          other.rawLink == this.rawLink &&
          other.name == this.name &&
          other.flag == this.flag &&
          other.country == this.country &&
          other.savedAt == this.savedAt &&
          other.updateIntervalHours == this.updateIntervalHours);
}

class PatternihaServersCompanion extends UpdateCompanion<PatternihaServer> {
  final Value<int> id;
  final Value<String> rawLink;
  final Value<String> name;
  final Value<String> flag;
  final Value<String> country;
  final Value<DateTime> savedAt;
  final Value<int> updateIntervalHours;
  const PatternihaServersCompanion({
    this.id = const Value.absent(),
    this.rawLink = const Value.absent(),
    this.name = const Value.absent(),
    this.flag = const Value.absent(),
    this.country = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.updateIntervalHours = const Value.absent(),
  });
  PatternihaServersCompanion.insert({
    this.id = const Value.absent(),
    required String rawLink,
    this.name = const Value.absent(),
    this.flag = const Value.absent(),
    this.country = const Value.absent(),
    required DateTime savedAt,
    this.updateIntervalHours = const Value.absent(),
  })  : rawLink = Value(rawLink),
        savedAt = Value(savedAt);
  static Insertable<PatternihaServer> custom({
    Expression<int>? id,
    Expression<String>? rawLink,
    Expression<String>? name,
    Expression<String>? flag,
    Expression<String>? country,
    Expression<DateTime>? savedAt,
    Expression<int>? updateIntervalHours,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rawLink != null) 'raw_link': rawLink,
      if (name != null) 'name': name,
      if (flag != null) 'flag': flag,
      if (country != null) 'country': country,
      if (savedAt != null) 'saved_at': savedAt,
      if (updateIntervalHours != null)
        'update_interval_hours': updateIntervalHours,
    });
  }

  PatternihaServersCompanion copyWith(
      {Value<int>? id,
      Value<String>? rawLink,
      Value<String>? name,
      Value<String>? flag,
      Value<String>? country,
      Value<DateTime>? savedAt,
      Value<int>? updateIntervalHours}) {
    return PatternihaServersCompanion(
      id: id ?? this.id,
      rawLink: rawLink ?? this.rawLink,
      name: name ?? this.name,
      flag: flag ?? this.flag,
      country: country ?? this.country,
      savedAt: savedAt ?? this.savedAt,
      updateIntervalHours: updateIntervalHours ?? this.updateIntervalHours,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (rawLink.present) {
      map['raw_link'] = Variable<String>(rawLink.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (flag.present) {
      map['flag'] = Variable<String>(flag.value);
    }
    if (country.present) {
      map['country'] = Variable<String>(country.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (updateIntervalHours.present) {
      map['update_interval_hours'] = Variable<int>(updateIntervalHours.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PatternihaServersCompanion(')
          ..write('id: $id, ')
          ..write('rawLink: $rawLink, ')
          ..write('name: $name, ')
          ..write('flag: $flag, ')
          ..write('country: $country, ')
          ..write('savedAt: $savedAt, ')
          ..write('updateIntervalHours: $updateIntervalHours')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MahsaServersTable mahsaServers = $MahsaServersTable(this);
  late final $PatternihaServersTable patternihaServers =
      $PatternihaServersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [mahsaServers, patternihaServers];
}

typedef $$MahsaServersTableCreateCompanionBuilder = MahsaServersCompanion
    Function({
  Value<int> id,
  required String rawLink,
  required DateTime savedAt,
  Value<int> updateIntervalHours,
});
typedef $$MahsaServersTableUpdateCompanionBuilder = MahsaServersCompanion
    Function({
  Value<int> id,
  Value<String> rawLink,
  Value<DateTime> savedAt,
  Value<int> updateIntervalHours,
});

class $$MahsaServersTableFilterComposer
    extends Composer<_$AppDatabase, $MahsaServersTable> {
  $$MahsaServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rawLink => $composableBuilder(
      column: $table.rawLink, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updateIntervalHours => $composableBuilder(
      column: $table.updateIntervalHours,
      builder: (column) => ColumnFilters(column));
}

class $$MahsaServersTableOrderingComposer
    extends Composer<_$AppDatabase, $MahsaServersTable> {
  $$MahsaServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rawLink => $composableBuilder(
      column: $table.rawLink, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updateIntervalHours => $composableBuilder(
      column: $table.updateIntervalHours,
      builder: (column) => ColumnOrderings(column));
}

class $$MahsaServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MahsaServersTable> {
  $$MahsaServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rawLink =>
      $composableBuilder(column: $table.rawLink, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<int> get updateIntervalHours => $composableBuilder(
      column: $table.updateIntervalHours, builder: (column) => column);
}

class $$MahsaServersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MahsaServersTable,
    MahsaServer,
    $$MahsaServersTableFilterComposer,
    $$MahsaServersTableOrderingComposer,
    $$MahsaServersTableAnnotationComposer,
    $$MahsaServersTableCreateCompanionBuilder,
    $$MahsaServersTableUpdateCompanionBuilder,
    (
      MahsaServer,
      BaseReferences<_$AppDatabase, $MahsaServersTable, MahsaServer>
    ),
    MahsaServer,
    PrefetchHooks Function()> {
  $$MahsaServersTableTableManager(_$AppDatabase db, $MahsaServersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MahsaServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MahsaServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MahsaServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> rawLink = const Value.absent(),
            Value<DateTime> savedAt = const Value.absent(),
            Value<int> updateIntervalHours = const Value.absent(),
          }) =>
              MahsaServersCompanion(
            id: id,
            rawLink: rawLink,
            savedAt: savedAt,
            updateIntervalHours: updateIntervalHours,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String rawLink,
            required DateTime savedAt,
            Value<int> updateIntervalHours = const Value.absent(),
          }) =>
              MahsaServersCompanion.insert(
            id: id,
            rawLink: rawLink,
            savedAt: savedAt,
            updateIntervalHours: updateIntervalHours,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MahsaServersTable, MahsaServer>(table),
                    BaseReferences<_$AppDatabase, $MahsaServersTable,
                        MahsaServer>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MahsaServersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MahsaServersTable,
    MahsaServer,
    $$MahsaServersTableFilterComposer,
    $$MahsaServersTableOrderingComposer,
    $$MahsaServersTableAnnotationComposer,
    $$MahsaServersTableCreateCompanionBuilder,
    $$MahsaServersTableUpdateCompanionBuilder,
    (
      MahsaServer,
      BaseReferences<_$AppDatabase, $MahsaServersTable, MahsaServer>
    ),
    MahsaServer,
    PrefetchHooks Function()>;
typedef $$PatternihaServersTableCreateCompanionBuilder
    = PatternihaServersCompanion Function({
  Value<int> id,
  required String rawLink,
  Value<String> name,
  Value<String> flag,
  Value<String> country,
  required DateTime savedAt,
  Value<int> updateIntervalHours,
});
typedef $$PatternihaServersTableUpdateCompanionBuilder
    = PatternihaServersCompanion Function({
  Value<int> id,
  Value<String> rawLink,
  Value<String> name,
  Value<String> flag,
  Value<String> country,
  Value<DateTime> savedAt,
  Value<int> updateIntervalHours,
});

class $$PatternihaServersTableFilterComposer
    extends Composer<_$AppDatabase, $PatternihaServersTable> {
  $$PatternihaServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rawLink => $composableBuilder(
      column: $table.rawLink, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get flag => $composableBuilder(
      column: $table.flag, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get country => $composableBuilder(
      column: $table.country, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updateIntervalHours => $composableBuilder(
      column: $table.updateIntervalHours,
      builder: (column) => ColumnFilters(column));
}

class $$PatternihaServersTableOrderingComposer
    extends Composer<_$AppDatabase, $PatternihaServersTable> {
  $$PatternihaServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rawLink => $composableBuilder(
      column: $table.rawLink, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get flag => $composableBuilder(
      column: $table.flag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get country => $composableBuilder(
      column: $table.country, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updateIntervalHours => $composableBuilder(
      column: $table.updateIntervalHours,
      builder: (column) => ColumnOrderings(column));
}

class $$PatternihaServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $PatternihaServersTable> {
  $$PatternihaServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get rawLink =>
      $composableBuilder(column: $table.rawLink, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get flag =>
      $composableBuilder(column: $table.flag, builder: (column) => column);

  GeneratedColumn<String> get country =>
      $composableBuilder(column: $table.country, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);

  GeneratedColumn<int> get updateIntervalHours => $composableBuilder(
      column: $table.updateIntervalHours, builder: (column) => column);
}

class $$PatternihaServersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PatternihaServersTable,
    PatternihaServer,
    $$PatternihaServersTableFilterComposer,
    $$PatternihaServersTableOrderingComposer,
    $$PatternihaServersTableAnnotationComposer,
    $$PatternihaServersTableCreateCompanionBuilder,
    $$PatternihaServersTableUpdateCompanionBuilder,
    (
      PatternihaServer,
      BaseReferences<_$AppDatabase, $PatternihaServersTable, PatternihaServer>
    ),
    PatternihaServer,
    PrefetchHooks Function()> {
  $$PatternihaServersTableTableManager(
      _$AppDatabase db, $PatternihaServersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PatternihaServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PatternihaServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PatternihaServersTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> rawLink = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> flag = const Value.absent(),
            Value<String> country = const Value.absent(),
            Value<DateTime> savedAt = const Value.absent(),
            Value<int> updateIntervalHours = const Value.absent(),
          }) =>
              PatternihaServersCompanion(
            id: id,
            rawLink: rawLink,
            name: name,
            flag: flag,
            country: country,
            savedAt: savedAt,
            updateIntervalHours: updateIntervalHours,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String rawLink,
            Value<String> name = const Value.absent(),
            Value<String> flag = const Value.absent(),
            Value<String> country = const Value.absent(),
            required DateTime savedAt,
            Value<int> updateIntervalHours = const Value.absent(),
          }) =>
              PatternihaServersCompanion.insert(
            id: id,
            rawLink: rawLink,
            name: name,
            flag: flag,
            country: country,
            savedAt: savedAt,
            updateIntervalHours: updateIntervalHours,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$PatternihaServersTable, PatternihaServer>(
                        table),
                    BaseReferences<_$AppDatabase, $PatternihaServersTable,
                        PatternihaServer>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PatternihaServersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PatternihaServersTable,
    PatternihaServer,
    $$PatternihaServersTableFilterComposer,
    $$PatternihaServersTableOrderingComposer,
    $$PatternihaServersTableAnnotationComposer,
    $$PatternihaServersTableCreateCompanionBuilder,
    $$PatternihaServersTableUpdateCompanionBuilder,
    (
      PatternihaServer,
      BaseReferences<_$AppDatabase, $PatternihaServersTable, PatternihaServer>
    ),
    PatternihaServer,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MahsaServersTableTableManager get mahsaServers =>
      $$MahsaServersTableTableManager(_db, _db.mahsaServers);
  $$PatternihaServersTableTableManager get patternihaServers =>
      $$PatternihaServersTableTableManager(_db, _db.patternihaServers);
}
