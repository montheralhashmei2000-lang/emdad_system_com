import '../../db/app_database.dart';
import '../../repos/catalog_repo.dart';
import '../xlsx_reader.dart';
import 'template_kind.dart';
import 'template_table.dart';

/// `DateTime.tryParse` متسامحٌ يُدوِّر «2026-13-45» إلى تاريخٍ آخر بدل رفضه، فيُقارَن
/// الناتج بالمدخل: ما لم يعد كما كُتب فليس تاريخًا حقيقيًّا.
bool isRealIsoDate(String date) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) return false;
  final d = DateTime.tryParse(date);
  if (d == null) return false;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}' == date;
}

/// صفٌّ مقبول من قالب «صنف + كميات بوحدات»: الصنف والأجزاء ومجموعها بالأساس.
class UnitQtyRow {
  const UnitQtyRow({required this.sheetRow, required this.item, required this.parts, required this.baseQty});

  final int sheetRow;
  final Item item;

  /// (الوحدة، الكمية المكتوبة بها) بترتيب الأعمدة.
  final List<(ItemUnit, double)> parts;

  /// مجموع (الكمية × معامل الوحدة) بوحدة الأساس، مقرَّبًا إلى ثلاث خانات.
  final double baseQty;

  Map<String, double> get countsByUnit => {for (final (u, q) in parts) u.name: q};
}

/// نتيجة تحليل صف: الصف المقبول أو سبب الرفض، ومعه الصنف إن عُرف (ليحميه
/// فشلُ صفّه من الحذف في نمط الاستبدال).
typedef UnitQtyParse = ({UnitQtyRow? row, String? error, Item? item});

/// محلّل قالبي «الأرصدة الافتتاحية» و«العد الفعلي» — أعمدتهما واحدة.
///
/// الصنف يُعرف بكوده والاسم للتحقق وحده، والوحدة يجب أن تكون من [allowedUnits]
/// (وحدات الصنف كلها للافتتاحي؛ وللجرد ما تعرضه شاشة الجرد).
class UnitQtyParser {
  UnitQtyParser(this._catalog, this._byCode);

  final CatalogRepo _catalog;
  final Map<String, Item> _byCode;

  static Future<UnitQtyParser> create(CatalogRepo catalog) async {
    final byCode = <String, Item>{};
    for (final i in await catalog.items()) {
      if (i.code.isNotEmpty) byCode.putIfAbsent(i.code, () => i);
    }
    return UnitQtyParser(catalog, byCode);
  }

  /// الصنف بكود الخلية، أو `null`.
  Item? itemOf(TemplateTable t, List<XCell?> row) => _byCode[latinDigits(cellText(t.cell(row, 'كود الصنف')))];

  UnitQtyParse parse(
    TemplateTable t,
    List<XCell?> row,
    int n, {
    required List<ItemUnit> Function(Item) allowedUnits,
  }) {
    UnitQtyParse fail(String why, [Item? item]) => (row: null, error: why, item: item);

    final code = latinDigits(cellText(t.cell(row, 'كود الصنف')));
    if (code.isEmpty) return fail('كود الصنف مطلوب');
    final item = _byCode[code];
    if (item == null) return fail('لا يوجد صنف بالكود «$code» في الأصناف');
    final name = cellText(t.cell(row, 'اسم الصنف'));
    if (name.isEmpty) return fail('اسم الصنف مطلوب', item);
    if (normalizeHeader(name) != normalizeHeader(item.name)) {
      return fail('الاسم «$name» لا يطابق الصنف ${item.code} «${item.name}»', item);
    }

    final allowed = allowedUnits(item);
    final parts = <(ItemUnit, double)>[];
    for (var i = 1; i <= 3; i++) {
      final unitName = cellText(t.cell(row, 'وحدة $i'));
      final qtyCell = t.cell(row, 'كمية وحدة $i');
      if (unitName.isEmpty) {
        if (i == 1) return fail('وحدة 1 مطلوبة', item);
        if (hasContent(qtyCell)) return fail('كمية وحدة $i بلا وحدة $i', item);
        continue;
      }
      final unit = allowed.where((u) => normalizeHeader(u.name) == normalizeHeader(unitName)).firstOrNull;
      if (unit == null) {
        return fail('الوحدة «$unitName» ليست من وحدات الصنف (${allowed.map((u) => u.name).join('، ')})', item);
      }
      if (parts.any((p) => p.$1.name == unit.name)) return fail('الوحدة «$unitName» مكررة في الصف', item);
      if (!hasContent(qtyCell)) return fail('كمية وحدة $i مطلوبة', item);
      final qty = cellNum(qtyCell);
      if (qty == null || qty.isNaN || qty.isInfinite) {
        return fail('كمية وحدة $i «${cellText(qtyCell)}» ليست رقمًا', item);
      }
      if (qty < 0) return fail('كمية وحدة $i يجب أن تكون صفرًا أو أكثر', item);
      parts.add((unit, qty));
    }

    var base = 0.0;
    for (final (u, q) in parts) {
      base += q * (u.factor <= 0 ? 1 : u.factor);
    }
    base = (base * 1000).round() / 1000;
    return (row: UnitQtyRow(sheetRow: n, item: item, parts: parts, baseQty: base), error: null, item: item);
  }

  /// وحدات الصنف كلها.
  List<ItemUnit> allUnits(Item item) => _catalog.unitsOf(item);

  /// ما تعرضه شاشة الجرد للعد: أكبر ثلاث وحدات.
  List<ItemUnit> countedUnits(Item item) => _catalog.unitsDescending(item).take(3).toList();
}
