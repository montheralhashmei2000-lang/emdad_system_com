import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/pbkdf2.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/legacy_import.dart';
import 'package:imdad/data/repos/archive_auto.dart';
import 'package:imdad/data/repos/camp_ledger_repo.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ذهابٌ وإياب: ما يصدّره جهازٌ يستورده آخر **كما هو**.
///
/// المصدِّر والمستورد كُتبا كلٌّ على حدة، ولكلٍّ اختباره: التصدير يُفحص بقائمة
/// والاستيراد بخريطة — فلم يلتقيا قط، وبقيت الإعدادات لا تُزامَن من أول إصدار.
/// هنا لا تُكتب الحمولة باليد: تُبذر القاعدة من مخطّطها نفسه (كل جدولٍ مزامَن،
/// كل عمود)، ثم تُصدَّر وتُستورد وتُقارن القاعدتان عمودًا عمودًا.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase master;
  late AppDatabase branch;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    master = AppDatabase.forTesting(NativeDatabase.memory());
    branch = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await master.close();
    await branch.close();
  });

  Future<void> sync(AppDatabase from, AppDatabase to) async =>
      LegacyImporter(to).importJson(await DataExporter(from).toMap(includeUsers: true));

  group('الجداول', () {
    /// قيمةٌ مميَّزة لكل عمود بحسب نوعه — تُكشف بها أي خانةٍ أسقطها الدمج.
    Object valueFor(String table, GeneratedColumn c, int n) {
      if (c.name == 'iterations') return Pbkdf2.iterations; // يُحصر عمدًا في المدى المقبول
      return switch (c.type) {
        DriftSqlType.bool => 1,
        DriftSqlType.int || DriftSqlType.bigInt => 7 + n,
        DriftSqlType.double => 2.5 + n,
        DriftSqlType.dateTime => DateTime.utc(2026, 1, 2 + n, 3, 4, 5).millisecondsSinceEpoch ~/ 1000,
        _ => '$table.${c.name}.$n',
      };
    }

    Future<void> seed(AppDatabase db) async {
      for (final t in db.allTables) {
        final name = t.actualTableName;
        if (!SyncMarks.entities.containsKey(name) || name == 'app_settings') continue;
        for (var n = 0; n < 2; n++) {
          final cols = t.$columns;
          await db.customStatement(
            'INSERT INTO "$name" (${cols.map((c) => '"${c.name}"').join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) valueFor(name, c, n)],
          );
        }
      }
    }

    Future<List<Map<String, Object?>>> rowsOf(AppDatabase db, String table, String pk) async =>
        [for (final r in await db.customSelect('SELECT * FROM "$table" ORDER BY "$pk"').get()) r.data];

    /// ما لا يعبر **عمدًا**: حالةُ هذا الجهاز وحده.
    const intended = {
      'users.failed_attempts', // عدّاد محاولات الدخول على هذا الجهاز
      'users.locked_until', // قفل الدخول على هذا الجهاز
    };

    /// ما لا يعبر **ولا ينبغي** — دَينٌ معروف (CLAUDE.md §8 البند 43): المستورد
    /// يكتب ختم لحظة الاستيراد أو لا يكتب شيئًا، فيضيع تاريخ الإنشاء/التعديل
    /// الأصلي في الطرف الآخر. الدمج لا يتأثر (العلامات في `sync_marks` لا هنا).
    /// كل سطرٍ يُصلَح يُحذف من هنا — والاختبار الثاني يفشل إن بقي بعد إصلاحه.
    const knownGaps = {
      'users.created_at',
      'items.created_at',
      'opening_balances.created_at',
      'strengths.created_at',
      'kitchen_logs.created_at',
      'entitlements.updated_at',
      'assets.updated_at',
      'camp_ledgers.updated_at',
      'camp_stock_limits.updated_at',
      'fuel_allocations.updated_at',
      'fuel_settings_rows.updated_at',
      'fuel_stocktakes.updated_at',
      'meal_plans.updated_at',
      'ration_orders.updated_at',
    };

    Future<Set<String>> roundTripDiffs() async {
      await seed(master);
      await sync(master, branch);
      final diffs = <String>{};
      for (final e in SyncMarks.entities.entries) {
        if (e.key == 'app_settings') continue;
        final a = await rowsOf(master, e.key, e.value);
        var b = await rowsOf(branch, e.key, e.value);
        // الطرف المستقبِل يكتب صفوف تدقيقه هو (نتائج الدمج) — تُقارن صفوف المصدر وحدها.
        if (e.key == 'audit_logs') {
          final ids = {for (final r in a) r['id']};
          b = [for (final r in b) if (ids.contains(r['id'])) r];
        }
        if (a.length != b.length) {
          diffs.add('${e.key}: ${a.length} صفًّا هنا و${b.length} هناك');
          continue;
        }
        for (var i = 0; i < a.length; i++) {
          for (final col in a[i].keys) {
            if (a[i][col] != b[i][col]) diffs.add('${e.key}.$col');
          }
        }
      }
      return diffs;
    }

    test('كل جدولٍ مزامَن يعبر كما هو، عدا المقصود والدَّين المعروف', () async {
      final unexpected = (await roundTripDiffs()).difference({...intended, ...knownGaps});
      expect(unexpected, isEmpty, reason: 'لا يعبر الدمجَ: ${unexpected.join('، ')}');
    });

    test('قائمة الدَّين ليست قديمة (ما أُصلح يُحذف منها)', () async {
      final stale = knownGaps.difference(await roundTripDiffs());
      expect(stale, isEmpty, reason: 'أُصلح ولم يُحذف من knownGaps: ${stale.join('، ')}');
    });
  });

  group('الإعدادات', () {
    test('المزامَنة تعبر بقيمها: printForms وnumbers وprintLayout وorg', () async {
      final repo = SettingsRepo(master);
      final values = {
        SettingsRepo.printFormsKey: {
          'issue': {'orgLine1': 'قيادة المنطقة', 'fontSize': 11},
        },
        SettingsRepo.numbersKey: {'screenDigits': 'latin', 'moneyDecimals': 3},
        SettingsRepo.printLayoutKey: {'orgLine1': 'الجهة', 'showExpiry': true},
        SettingsRepo.orgKey: {'name': 'الوحدة'},
      };
      for (final e in values.entries) {
        await repo.write(e.key, e.value);
      }

      await sync(master, branch);

      for (final e in values.entries) {
        expect(await SettingsRepo(branch).read(e.key), e.value, reason: 'الإعداد ${e.key} لم يعبر');
      }
    });

    test('الاستعادة من ملف تحمل الإعدادات كذلك (المسار نفسه)', () async {
      await SettingsRepo(master).write(SettingsRepo.orgKey, {'name': 'الوحدة'});
      await LegacyImporter(branch).importJson(await DataExporter(master).toMap(includeUsers: true), trusted: true);
      expect(await SettingsRepo(branch).read(SettingsRepo.orgKey), {'name': 'الوحدة'});
    });

    test('المحلية لا تعبر ولو صار الاستيراد يعمل', () async {
      for (final k in SettingsRepo.localOnlyKeys) {
        await SettingsRepo(master).write(k, {'from': 'master'});
        await SettingsRepo(branch).write(k, {'from': 'branch'});
      }
      await sync(master, branch);
      for (final k in SettingsRepo.localOnlyKeys) {
        expect(await SettingsRepo(branch).read(k), {'from': 'branch'}, reason: 'المفتاح المحلي $k دُهس');
      }
    });

    test('التصفية التلقائية لا تنتشر (لا رجعة فيها، وتصطدم بفهرسها الفريد)', () async {
      await CampLedgerRepo(master).setAutoSettle(true);
      await sync(master, branch);
      expect(await CampLedgerRepo(branch).isAutoSettle(), isFalse);
    });

    test('الأرشفة التلقائية لا تنتشر (الأرشيف على قرص كل جهاز)', () async {
      await ArchiveAuto(master).save(const ArchiveAutoSettings(enabled: true, ops: {'issue': true}));
      await sync(master, branch);
      expect((await ArchiveAuto(branch).load()).enabled, isFalse);
    });

    test('ختمان متساويان على قيمتين مختلفتين ⇒ يلتقيان من أول دورة ويثبتان', () async {
      // حالُ الأجهزة القائمة: الاستيراد المعطوب ثبّت ختم القرين على صفٍّ لم يكتبه.
      const stamp = 1790000000000;
      await SettingsRepo(master).write(SettingsRepo.orgKey, {'name': 'أ'});
      await SettingsRepo(branch).write(SettingsRepo.orgKey, {'name': 'ب'});
      for (final db in [master, branch]) {
        await SyncMarks(db).put(const SyncMark(entity: 'app_settings', rowId: 'org', updatedAt: stamp));
      }

      for (var cycle = 0; cycle < 3; cycle++) {
        await sync(master, branch);
        await sync(branch, master);
        final a = await SettingsRepo(master).read(SettingsRepo.orgKey);
        final b = await SettingsRepo(branch).read(SettingsRepo.orgKey);
        expect(a, b, reason: 'الدورة ${cycle + 1}: لم يلتقيا');
        expect(a, {'name': 'ب'}, reason: 'الفائز ثابتٌ لا يتبدّل بين الدورات');
      }
    });

    test('تعديلٌ أحدث يفوز كما كان', () async {
      await SettingsRepo(master).write(SettingsRepo.orgKey, {'name': 'قديم'});
      await sync(master, branch);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await SettingsRepo(branch).write(SettingsRepo.orgKey, {'name': 'جديد'});
      await sync(branch, master);
      expect(await SettingsRepo(master).read(SettingsRepo.orgKey), {'name': 'جديد'});
    });
  });
}
