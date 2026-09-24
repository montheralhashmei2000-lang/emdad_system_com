import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/assets_repo.dart';
import 'package:imdad/data/repos/camp_ledger_repo.dart';
import 'package:imdad/data/repos/catalog_repo.dart';
import 'package:imdad/data/repos/notifications_repo.dart';
import 'package:imdad/domain/assets.dart';
import 'package:imdad/domain/notification_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// التنبيهات: اشتقاقها من الحالة، وثبات معرّفاتها، وحجبها بالصلاحيات.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  group('قواعد العرض', () {
    AppNotification n(String id, NotifySeverity s, {bool read = false}) => AppNotification(
          id: id,
          kind: NotifyKind.campStockLow,
          severity: s,
          title: id,
          body: '',
          read: read,
        );

    test('الأخطر أولًا، ثم غير المقروء', () {
      final sorted = NotifyRules.sort([
        n('a', NotifySeverity.info),
        n('b', NotifySeverity.danger),
        n('c', NotifySeverity.warning),
      ]);
      expect(sorted.map((x) => x.id), ['b', 'c', 'a']);

      final byRead = NotifyRules.sort([
        n('read', NotifySeverity.danger, read: true),
        n('new', NotifySeverity.danger),
      ]);
      expect(byRead.first.id, 'new');
    });

    test('النوع الواحد يُقصّ ويُلخَّص الباقي', () {
      final many = [
        for (var i = 0; i < NotifyRules.perKindCap + 5; i++) n('n$i', NotifySeverity.info),
      ];
      final capped = NotifyRules.cap(many);
      expect(capped, hasLength(NotifyRules.perKindCap + 1));
      expect(capped.last.id, 'more.campStockLow');
      expect(capped.last.title, contains('5'));
    });

    test('عدّ غير المقروء', () {
      expect(
        NotifyRules.unreadOf([n('a', NotifySeverity.info), n('b', NotifySeverity.info, read: true)]),
        1,
      );
    });
  });

  group('اشتقاق التنبيهات', () {
    Future<String> expiredAsset() => AssetsRepo(db).save(
          name: 'فرن قديم',
          assetType: AssetType.oven,
          acquisitionDate: '2020-01-01',
          lifespanMonths: 12,
        );

    test('أصل انقضى عمره يُنبَّه عليه', () async {
      await expiredAsset();
      final items = await NotificationsRepo(db).scan();
      expect(items.any((n) => n.kind == NotifyKind.assetExpired), isTrue);
    });

    test('أصل خارج الخدمة لا يُنبَّه عليه', () async {
      await AssetsRepo(db).save(
        name: 'فرن تالف',
        assetType: AssetType.oven,
        status: AssetStatus.damaged,
        acquisitionDate: '2020-01-01',
        lifespanMonths: 12,
      );
      final items = await NotificationsRepo(db).scan();
      expect(items.any((n) => n.kind == NotifyKind.assetExpired), isFalse,
          reason: 'نُبِّه على أصل شُطب أصلًا');
    });

    test('المعرّف ثابت لنفس الحالة فلا يعود بعد قراءته', () async {
      final id = await expiredAsset();
      final repo = NotificationsRepo(db);

      final first = await repo.scan();
      final target = first.firstWhere((n) => n.id == 'asset.expired.$id');
      expect(target.read, isFalse);

      await repo.markRead(target.id);
      final second = await repo.scan();
      expect(second.firstWhere((n) => n.id == 'asset.expired.$id').read, isTrue,
          reason: 'تغيّر المعرّف بين الفحصين فعاد التنبيه');
    });

    test('زوال الحالة يُزيل التنبيه بلا حذف يدوي', () async {
      final id = await expiredAsset();
      final repo = NotificationsRepo(db);
      expect((await repo.scan()).any((n) => n.id == 'asset.expired.$id'), isTrue);

      // شُطب الأصل: الحالة زالت.
      await AssetsRepo(db).save(
        id: id,
        name: 'فرن قديم',
        assetType: AssetType.oven,
        status: AssetStatus.consumed,
        acquisitionDate: '2020-01-01',
        lifespanMonths: 12,
      );
      expect((await repo.scan()).any((n) => n.id == 'asset.expired.$id'), isFalse,
          reason: 'بقي تنبيه على حالة عولجت');
    });

    test('الصلاحيات تحجب التنبيه كما تحجب الشاشة', () async {
      await expiredAsset();
      final items = await NotificationsRepo(db).scan(allowed: {'campDashboard'});
      expect(items.any((n) => n.kind == NotifyKind.assetExpired), isFalse,
          reason: 'سرّب الجرس ما حجبته الصلاحيات');
    });

    test('تنظيف حالة القراءة لا يمسّ المعرّفات القائمة', () async {
      final repo = NotificationsRepo(db);
      await repo.markRead('ghost.id');
      await repo.markRead('live.id');
      await repo.prune(['live.id']);

      final prefs = await SharedPreferences.getInstance();
      final kept = prefs.getStringList('imdad.notify.read') ?? const [];
      expect(kept, ['live.id']);
    });
  });

  group('تنبيه الرصيد السالب', () {
    test('استهلاك بلا استلام يُنبَّه عليه ويفتح السجل', () async {
      await db.into(db.beneficiaryUnits).insert(BeneficiaryUnitsCompanion.insert(
            id: 'camp1',
            name: 'المعسكر',
            isCamp: const Value(true),
          ));
      await CatalogRepo(db).saveItem(
        code: 'X1',
        name: 'رز',
        baseUnit: 'كجم',
        units: const [ItemUnit(name: 'كجم', factor: 1, isBase: true)],
      );
      final item = (await CatalogRepo(db).items()).single;
      final now = DateTime.now();
      await db.into(db.campLedgers).insert(CampLedgersCompanion.insert(
            id: 'cl1',
            campId: 'camp1',
            campName: const Value('المعسكر'),
            itemId: item.id,
            itemName: const Value('رز'),
            year: now.year,
            month: now.month,
            consumedKitchen: const Value(300),
          ));

      final items = await NotificationsRepo(db).scan();
      final neg = items.where((n) => n.kind == NotifyKind.stockNegative);
      expect(neg, hasLength(1));
      expect(neg.single.kind.route, 'campLedger');
    });
  });

  group('تنبيه التصفية', () {
    test('شهر انقضى ولم يُصفَّ يُنبَّه عليه', () async {
      final now = DateTime.now();
      final year = now.month == 1 ? now.year - 1 : now.year;
      final month = now.month == 1 ? 12 : now.month - 1;
      await db.into(db.campLedgers).insert(CampLedgersCompanion.insert(
            id: 'cl1',
            campId: 'camp1',
            campName: const Value('المعسكر'),
            itemId: 'i1',
            itemName: const Value('رز'),
            year: year,
            month: month,
            entitlementTotal: const Value(500),
          ));

      final items = await NotificationsRepo(db).scan();
      expect(items.any((n) => n.kind == NotifyKind.settlementDue), isTrue);
    });

    test('التصفية التلقائية مطفأة افتراضيًا', () async {
      final repo = CampLedgerRepo(db);
      expect(await repo.isAutoSettle(), isFalse);
      final res = await repo.autoSettleIfDue();
      expect(res.ok, isFalse);
      expect(res.error, contains('مطفأة'));
    });

    test('تفعيلها يُحفظ ويُقرأ', () async {
      final repo = CampLedgerRepo(db);
      await repo.setAutoSettle(true);
      expect(await repo.isAutoSettle(), isTrue);
    });
  });
}
