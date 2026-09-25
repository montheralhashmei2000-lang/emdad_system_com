import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';

/// الترحيل يحتمل قاعدةً سبقت طابَعها.
///
/// جهازٌ فُتحت عليه نسخةٌ أحدث ثم نسخةٌ أقدم يُخفَّض طابَع قاعدته وتبقى
/// أعمدتُها. فإن رُقّي بعدها أعاد الترحيل إضافةَ عمودٍ قائم، فتُرمى
/// `duplicate column name` **أثناء فتح القاعدة** — فلا يفتح التطبيق أصلًا،
/// ولا يعرض خطأً مفهومًا، ولا سبيل للمستخدم إلى إصلاحه من داخله.
///
/// وقع هذا فعلًا عند تبادل نسختين في يوم واحد، فهذه الاختبارات تحرسه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('imdad_mig_idem');
    file = File('${dir.path}/db.sqlite');
  });

  tearDown(() async {
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // يبقى مقفلًا أحيانًا على ويندوز — لا يعني فشلًا.
      }
    }
  });

  /// يفتح القاعدة ويغلقها، فتجري الترحيلات.
  Future<void> open(Future<void> Function(AppDatabase db)? probe) async {
    final db = AppDatabase.forTesting(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();
    if (probe != null) await probe(db);
    await db.close();
  }

  test('طابَعٌ مخفَّض على قاعدة كاملة لا يُسقط الفتح', () async {
    // قاعدة بأحدث مخطط: كل الأعمدة والجداول موجودة.
    await open(null);

    // ثم يُخفَّض طابَعها كما يفعل فتحُ نسخةٍ أقدم من التطبيق.
    final down = AppDatabase.forTesting(NativeDatabase(file));
    await down.customStatement('PRAGMA user_version = 8');
    await down.close();

    // إعادة الفتح تُرقّيها من 8 — وكل عمود تحاول إضافته موجود سلفًا.
    await expectLater(open(null), completes,
        reason: 'الترحيل أسقط الفتح على قاعدة أعمدتها قائمة');
  });

  test('الترقية بعد الطابَع المخفَّض تحفظ البيانات', () async {
    await open((db) async {
      await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(id: 'wh1', name: 'الرئيسي'));
      await db.into(db.supplyAuthorities).insert(
          SupplyAuthoritiesCompanion.insert(id: 'a1', name: 'ركن الإمداد'));
    });

    final down = AppDatabase.forTesting(NativeDatabase(file));
    await down.customStatement('PRAGMA user_version = 10');
    await down.close();

    await open((db) async {
      expect((await db.select(db.warehouses).get()).single.name, 'الرئيسي');
      expect((await db.select(db.supplyAuthorities).get()).single.name,
          'ركن الإمداد');
    });
  });

  test('الطابَع يعود إلى أحدث إصدار بعد الترقية', () async {
    await open(null);
    final down = AppDatabase.forTesting(NativeDatabase(file));
    await down.customStatement('PRAGMA user_version = 3');
    await down.close();

    await open((db) async {
      final row =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.data.values.first, db.schemaVersion);
    });
  });

  test('جدولٌ محذوف يُعاد إنشاؤه عند الترقية', () async {
    await open(null);

    final down = AppDatabase.forTesting(NativeDatabase(file));
    await down.customStatement('DROP TABLE supply_authorities');
    await down.customStatement('PRAGMA user_version = 13');
    await down.close();

    await open((db) async {
      await db.into(db.supplyAuthorities).insert(
          SupplyAuthoritiesCompanion.insert(id: 'a2', name: 'قائد الفرقة'));
      expect((await db.select(db.supplyAuthorities).get()), hasLength(1));
    });
  });

  test('NULL في عمودٍ لا يقبله يُصلَح فلا تسقط القراءة', () async {
    await open((db) async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: 'r1',
            refNo: const Value('و-000001'),
            baseQty: const Value(4),
          ));
    });

    // تنقّلُ القاعدة بين نسختين يترك العمود بلا قيد NOT NULL وفيه NULL —
    // وهو ما وُجد فعلًا في قاعدة ميدانية تبادلت نسختين في يوم.
    final broken = AppDatabase.forTesting(NativeDatabase(file));
    await broken.customStatement('ALTER TABLE receipts DROP COLUMN expiry_date');
    await broken.customStatement('ALTER TABLE receipts ADD COLUMN expiry_date TEXT');
    await broken.customStatement('PRAGMA user_version = 13');
    await broken.close();

    await open((db) async {
      final r = (await db.select(db.receipts).get()).single;
      expect(r.expiryDate, isEmpty, reason: 'القراءة كانت تسقط قبل الإصلاح');
      expect(r.refNo, 'و-000001', reason: 'الإصلاح مسّ ما لا يخصّه');
      expect(r.baseQty, 4);
    });
  });

  test('عمودٌ فات بوابته يُستدرك عند الفتح — لا الطابَع وحده يحكم', () async {
    // هذه هي العطلة التي أوقفت التطبيق فعلًا: الطابَع 15 وبوابة v12 مرّت
    // دون أن تُنفَّذ قط، فبقي العمود مفقودًا وسقطت أول قراءة للسندات.
    await open((db) async {
      await db.into(db.receipts).insert(ReceiptsCompanion.insert(
            id: 'r1',
            refNo: const Value('و-000001'),
            baseQty: const Value(4),
          ));
    });

    final broken = AppDatabase.forTesting(NativeDatabase(file));
    await broken.customStatement('ALTER TABLE receipts DROP COLUMN expiry_date');
    // الطابَع يبقى أحدث إصدار: كل بوابات الترحيل ستُتخطّى.
    await broken.close();

    await open((db) async {
      final r = (await db.select(db.receipts).get()).single;
      expect(r.expiryDate, isEmpty, reason: 'العمود المفقود لم يُستدرك');
      expect(r.refNo, 'و-000001');
      expect(r.baseQty, 4, reason: 'الاستدراك مسّ بيانات قائمة');
    });
  });

  test('جدولٌ مفقود يُستدرك عند الفتح ولو كان الطابَع أحدث', () async {
    await open(null);
    final broken = AppDatabase.forTesting(NativeDatabase(file));
    await broken.customStatement('DROP TABLE supply_authorities');
    await broken.close();

    await open((db) async {
      await db.into(db.supplyAuthorities).insert(
          SupplyAuthoritiesCompanion.insert(id: 'a9', name: 'رئيس الشعبة'));
      expect(await db.select(db.supplyAuthorities).get(), hasLength(1));
    });
  });

  test('عمودٌ واحد ناقص يُضاف والباقي لا يُمسّ', () async {
    await open((db) async {
      await db.into(db.rationOrders).insert(RationOrdersCompanion.insert(
            id: 'o1',
            refNo: const Value('ط-000001'),
            requestingWarehouse: const Value('الفرع'),
          ));
    });

    final down = AppDatabase.forTesting(NativeDatabase(file));
    await down.customStatement('DROP INDEX IF EXISTS ix_ration_kind');
    await down.customStatement(
        'ALTER TABLE ration_orders DROP COLUMN fulfill_kind');
    await down.customStatement('PRAGMA user_version = 13');
    await down.close();

    await open((db) async {
      final o = (await db.select(db.rationOrders).get()).single;
      expect(o.refNo, 'ط-000001', reason: 'السطر القائم تغيّر أثناء الترحيل');
      expect(o.fulfillKind, isEmpty);
      expect(o.orderKind, 'BRANCH');
    });
  });
}
