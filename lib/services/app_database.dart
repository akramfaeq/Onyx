// ─── AppDatabase — قاعدة بيانات Drift (SQLite) ─────────────────────
// نفس منهجية Hiddify: يستخدم SQLite لتخزين السيرفرات محلياً
// جدولان:
//   • mahsa_servers    — روابط Mahsa (تجديد كل 6 ساعات)
//   • patterniha_servers — سيرفرات Patterniha مع اسم وعلم (تجديد كل 24 ساعة)
//
// لتوليد الكود: flutter pub run build_runner build
// ────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// ─── جدول Mahsa ─────────────────────────────────────────────────────
class MahsaServers extends Table {
  IntColumn    get id                  => integer().autoIncrement()();
  TextColumn   get rawLink             => text()();
  DateTimeColumn get savedAt           => dateTime()();
  IntColumn    get updateIntervalHours => integer().withDefault(const Constant(6))();
}

// ─── جدول Patterniha ────────────────────────────────────────────────
class PatternihaServers extends Table {
  IntColumn    get id                  => integer().autoIncrement()();
  TextColumn   get rawLink             => text()();
  TextColumn   get name                => text().withDefault(const Constant(''))();
  TextColumn   get flag                => text().withDefault(const Constant('🌐'))();
  TextColumn   get country             => text().withDefault(const Constant(''))();
  DateTimeColumn get savedAt           => dateTime()();
  IntColumn    get updateIntervalHours => integer().withDefault(const Constant(24))();
}

// ─── تعريف الـ Database ──────────────────────────────────────────────
@DriftDatabase(tables: [MahsaServers, PatternihaServers])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // للاختبار فقط
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  // ──────────────────────────────────────────────────────────────────
  // Mahsa — عمليات CRUD
  // ──────────────────────────────────────────────────────────────────

  /// جلب كل روابط Mahsa مرتبة بالأحدث
  Future<List<MahsaServer>> getAllMahsaLinks() =>
      (select(mahsaServers)
            ..orderBy([(t) => OrderingTerm.desc(t.savedAt)]))
          .get();

  /// أحدث وقت حفظ لـ Mahsa — null إذا ما في بيانات
  Future<DateTime?> getMahsaLastSavedAt() async {
    final row = await (select(mahsaServers)
          ..orderBy([(t) => OrderingTerm.desc(t.savedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.savedAt;
  }

  /// حذف كل السيرفرات القديمة وإضافة الجديدة (atomic replace)
  Future<void> replaceMahsaLinks(List<String> links) async {
    await transaction(() async {
      await delete(mahsaServers).go();
      final now = DateTime.now();
      for (final link in links) {
        await into(mahsaServers).insert(
          MahsaServersCompanion.insert(
            rawLink: link,
            savedAt: now,
          ),
        );
      }
    });
  }

  /// امسح كل بيانات Mahsa
  Future<void> clearMahsaLinks() => delete(mahsaServers).go();

  // ──────────────────────────────────────────────────────────────────
  // Patterniha — عمليات CRUD
  // ──────────────────────────────────────────────────────────────────

  /// جلب كل سيرفرات Patterniha
  Future<List<PatternihaServer>> getAllPatternihaServers() =>
      (select(patternihaServers)
            ..orderBy([(t) => OrderingTerm.desc(t.savedAt)]))
          .get();

  /// أحدث وقت حفظ لـ Patterniha
  Future<DateTime?> getPatternihaLastSavedAt() async {
    final row = await (select(patternihaServers)
          ..orderBy([(t) => OrderingTerm.desc(t.savedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.savedAt;
  }

  /// حذف كل السيرفرات القديمة وإضافة الجديدة (atomic replace)
  Future<void> replacePatternihaServers({
    required List<String>  links,
    required List<String>  names,
    required List<String>  flags,
    required List<String>  countries,
  }) async {
    assert(
      links.length == names.length &&
      links.length == flags.length &&
      links.length == countries.length,
      'All lists must have same length',
    );
    await transaction(() async {
      await delete(patternihaServers).go();
      final now = DateTime.now();
      for (var i = 0; i < links.length; i++) {
        await into(patternihaServers).insert(
          PatternihaServersCompanion.insert(
            rawLink: links[i],
            name:    Value(names[i]),
            flag:    Value(flags[i]),
            country: Value(countries[i]),
            savedAt: now,
          ),
        );
      }
    });
  }

  /// امسح كل بيانات Patterniha
  Future<void> clearPatternihaServers() => delete(patternihaServers).go();
}

// ─── فتح الـ Database على الـ disk ──────────────────────────────────
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir  = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'onyx_vpn.db'));
    return NativeDatabase(file);
  });
}

// ─── Singleton — نفس Pattern هايدفاي ───────────────────────────────
AppDatabase? _dbInstance;

AppDatabase get db {
  _dbInstance ??= AppDatabase();
  return _dbInstance!;
}
