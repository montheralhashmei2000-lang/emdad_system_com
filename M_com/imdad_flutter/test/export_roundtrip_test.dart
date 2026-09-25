import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/migration/data_export.dart';
import 'package:imdad/data/migration/web_import.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/sync/sync_marks.dart';

/// المزامنة بين الأجهزة والنسخ الاحتياطي كلاهما = [DataExporter] ثم [WebImporter].
///
/// كل طرف يكتب قائمة حقوله بيده، فانفصلت القائمتان: نوع عملية الأسطوانة، والحد
/// الأدنى للصنف، وسجل تعديل المستندات وإلغائها، ومعامل المقرر… كانت تضيع عند كل
/// مزامنة. هذا الاختبار يقرأ أعمدة الجداول من SQLite نفسها، فأي عمود يُضاف لاحقًا
/// دون أن يُربط بالطرفين يُفشله.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// أعمدة لا تُنقل عمدًا.
  const localOnly = {
    // حالة قفل الدخول على هذا الجهاز وحده.
    'users.failed_attempts', 'users.locked_until',
  };
  // يُقارَن تاريخ الإنشاء في اختبار مستقل؛ هنا يختلف تمثيله بين الطرفين.
  const skippedEverywhere = {'created_at', 'updated_at'};

  /// إعدادات التطبيق تحمل هوية الجهاز ورمز تفعيله ومفاتيح الاقتران، فلا تُنقل كجدول.
  final tables = SyncMarks.entities.keys.where((t) => t != 'app_settings').toList();

  Future<void> fill(AppDatabase db, int pass) async {
    for (final t in tables) {
      final cols = await db.customSelect('PRAGMA table_info($t)').get();
      final names = <String>[];
      final vals = <Object?>[];
      for (final c in cols) {
        final n = c.read<String>('name');
        final type = c.read<String>('type').toUpperCase();
        names.add(n);
        if (n == 'id' || (t == 'entitlements' && n == 'item_id')) {
          vals.add('${t}_1');
        } else if (type.contains('INT')) {
          // التمريرتان بقيمتين مختلفتين: قيمة تطابق الافتراضي صدفة لا تكشف ضياع العمود.
          final isTime = n.endsWith('_at') || n.endsWith('_until');
          vals.add(isTime ? 1700000000 + pass : pass);
        } else if (type.contains('REAL')) {
          vals.add(pass == 0 ? 7.5 : 2.25);
        } else if (const ['permissions', 'details'].contains(n)) {
          vals.add('{"k":$pass}');
        } else if (const ['roles', 'units', 'facility_ids', 'camp_ids', 'warehouse_scope', 'edit_log', 'counts']
            .contains(n)) {
          vals.add('["z$pass"]');
        } else if (t == 'entitlements' && n == 'measure_unit_name') {
          vals.add('');
        } else {
          vals.add('v${pass}_$n');
        }
      }
      await db.customStatement(
        'INSERT INTO $t (${names.join(',')}) VALUES (${List.filled(names.length, '?').join(',')})',
        vals,
      );
    }
  }

  for (final pass in [0, 1]) {
    test('كل عمود يعبر التصدير والاستيراد (تمريرة ${pass + 1})', () async {
      final a = AppDatabase.forTesting(NativeDatabase.memory());
      final b = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(a.close);
      addTearDown(b.close);
      await fill(a, pass);

      final map = await DataExporter(a).toMap(includeUsers: true);
      await WebImporter(b).importJson(jsonDecode(jsonEncode(map)) as Map<String, dynamic>);

      final lost = <String>[];
      for (final t in tables) {
        final src = (await a.customSelect('SELECT * FROM $t').get()).single.data;
        final dst = await b.customSelect('SELECT * FROM $t').get();
        if (dst.isEmpty) {
          lost.add('$t: السجل كله');
          continue;
        }
        src.forEach((col, v) {
          if (skippedEverywhere.contains(col) || localOnly.contains('$t.$col')) return;
          if ('${dst.single.data[col]}' != '$v') lost.add('$t.$col ($v ⇐ ${dst.single.data[col]})');
        });
      }
      expect(lost, isEmpty, reason: 'أعمدة تضيع في المزامنة والنسخ الاحتياطي');
    });
  }

  test('المقرر لا يُقسم على معامل وحدته عند كل مزامنة', () async {
    final a = AppDatabase.forTesting(NativeDatabase.memory());
    final b = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(a.close);
    addTearDown(b.close);
    // الصنف موجود في الطرفين: هنا كان المستورد يقسم الكمية على معامل «كيس».
    for (final db in [a, b]) {
      await CatalogRepo(db).saveItem(
        id: 'rice',
        code: 'R1',
        name: 'أرز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true), ItemUnit(name: 'كيس', factor: 50)],
      );
    }
    await a.into(a.entitlements).insert(EntitlementsCompanion.insert(
          itemId: 'rice',
          qtyPerPerson: const Value(3),
          measureUnitName: const Value('كيس'),
          measureFactor: const Value(50),
        ));

    // ذهابًا وإيابًا مرتين، كما تفعل المزامنة التلقائية.
    for (var i = 0; i < 2; i++) {
      await WebImporter(b).importJson(jsonDecode(jsonEncode(await DataExporter(a).toMap())) as Map<String, dynamic>);
      await WebImporter(a).importJson(jsonDecode(jsonEncode(await DataExporter(b).toMap())) as Map<String, dynamic>);
    }

    for (final db in [a, b]) {
      final e = await db.select(db.entitlements).getSingle();
      expect(e.qtyPerPerson, 3);
      expect(e.measureFactor, 50);
    }
  });
}
