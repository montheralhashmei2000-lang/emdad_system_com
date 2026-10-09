import '../../db/app_database.dart';
import '../../repos/catalog_repo.dart';
import '../../repos/stocktake_repo.dart';
import 'template_kind.dart';
import 'template_report.dart';
import 'template_table.dart';
import 'unit_qty_rows.dart';

/// قالب العد الفعلي لأمر جرد مفتوح.
///
/// **لا منطق جديد هنا**: كل سطرٍ يمرّ بـ`StocktakeRepo.saveCount` نفسه الذي تستعمله
/// شاشة الجرد (يستبدل عدّ السطر، ويحسب الفرق عن الرصيد الدفتري، ولا يمسّ الأرصدة)،
/// وبقواعدها: الأمر `COUNTING`، والوحدات أكبر ثلاثٍ تعرضها الشاشة، والسطر المعدود
/// سابقًا لا يُصحَّح إلا بصلاحية التعديل، والعدّ المطابق لما سُجّل لا يُكتب، والصنف
/// غير المدرج في الأمر يُضاف من الشاشة بفعلٍ صريح فيُرفض هنا.
///
/// دمجٌ فقط: «الاستبدال» غير موجود في الشاشة فلا يوجد هنا.
class StocktakeCountTemplate {
  StocktakeCountTemplate(this.db)
      : _catalog = CatalogRepo(db),
        _repo = StocktakeRepo(db);

  final AppDatabase db;
  final CatalogRepo _catalog;
  final StocktakeRepo _repo;

  // ───────────────────────── التصدير

  /// أسطر الأمر: المعدود بكمياته، وغير المعدود بوحدته الصغرى وكميته فارغة (للتعبئة).
  Future<(List<List<Object?>>, List<String>)> exportRows({required String sessionId}) async {
    final session = await _repo.sessionById(sessionId);
    if (session == null) throw StateError('اختر أمر الجرد');
    final items = {for (final i in await _catalog.items()) i.id: i};
    final rows = <List<Object?>>[];
    var uncounted = 0;
    final lines = await _repo.lines(sessionId);
    lines.sort((a, b) => a.itemCode.compareTo(b.itemCode));
    for (final l in lines) {
      final item = items[l.itemId];
      if (item == null) continue;
      final shown = _catalog.unitsDescending(item).take(3).toList();
      final counts = StocktakeRepo.countsOf(l);
      final byUnit = counts.isNotEmpty
          ? counts
          : (l.countedQty == null ? <String, double>{} : StocktakeRepo.split(l.countedQty!, shown));
      final entries = [for (final u in shown) if (byUnit[u.name] != null) (u.name, byUnit[u.name]!)];
      if (entries.isEmpty) {
        uncounted++;
        rows.add([item.code, item.name, shown.last.name, null, null, null, null, null]);
        continue;
      }
      rows.add([
        item.code,
        item.name,
        for (var i = 0; i < 3; i++) ...[
          i < entries.length ? entries[i].$1 : null,
          i < entries.length ? entries[i].$2 : null,
        ],
      ]);
    }
    final warnings = <String>[
      if (uncounted > 0) '$uncounted صنف لم يُعدّ بعد — كميته فارغة، املأها وإلا رُفض صفّه عند الاستيراد',
      if (session.status != StocktakeRepo.counting) 'الأمر ${session.orderNo} ليس مفتوحًا للعد',
    ];
    return (rows, warnings);
  }

  // ───────────────────────── الاستيراد

  Future<TemplateReport> run(
    TemplateTable table, {
    required ImportMode mode,
    required bool dryRun,
    required String sessionId,
    required bool canEditCounted,
  }) async {
    if (mode == ImportMode.replace) {
      throw StateError('العد الفعلي يدعم الدمج فقط');
    }
    final session = await _repo.sessionById(sessionId);
    if (session == null) throw const FormatException('اختر أمر الجرد');
    if (session.status != StocktakeRepo.counting) {
      throw FormatException('أمر الجرد ${session.orderNo} ليس مفتوحًا للعد');
    }
    final report = TemplateReport(kind: TemplateKind.stocktakeCount, mode: mode, dryRun: dryRun);
    final parser = await UnitQtyParser.create(_catalog);
    final lineOf = {for (final l in await _repo.lines(sessionId)) l.itemId: l};

    final seen = <String, int>{};
    final todo = <(StocktakeLine, UnitQtyRow)>[];
    for (final (n, row) in table.dataRows()) {
      final p = parser.parse(table, row, n, allowedUnits: parser.countedUnits);
      if (p.row == null) {
        report.failed.add(RowIssue(n, p.error!));
        continue;
      }
      final r = p.row!;
      final dup = seen[r.item.id];
      if (dup != null) {
        report.failed.add(RowIssue(n, 'الصنف ${r.item.code} مكرر في الملف (أول ظهور في الصف $dup)'));
        continue;
      }
      seen[r.item.id] = n;

      final line = lineOf[r.item.id];
      if (line == null) {
        report.failed.add(RowIssue(n, 'الصنف ${r.item.code} «${r.item.name}» غير مدرج في أمر الجرد — يُضاف من شاشة الجرد'));
        continue;
      }
      final counted = line.countedQty != null;
      if (counted && !canEditCounted) {
        report.failed.add(RowIssue(n, '«${line.itemName}» سبق عدّه — تصحيح العد المسجَّل يتطلب صلاحية التعديل'));
        continue;
      }
      // الشاشة لا تكتب عدًّا مطابقًا لما سُجّل (`entered.toString() == before.toString()`).
      if (counted && r.countsByUnit.toString() == StocktakeRepo.countsOf(line).toString()) {
        report.unchanged++;
        continue;
      }
      counted ? report.updated++ : report.created++;
      todo.add((line, r));
    }

    Future<void> apply() async {
      for (final (line, r) in todo) {
        await _repo.saveCount(
          lineId: line.id,
          countsByUnit: r.countsByUnit,
          factors: {for (final (u, _) in r.parts) u.name: u.factor},
        );
      }
    }

    if (!dryRun && todo.isNotEmpty) await db.transaction(apply);
    return report;
  }
}
