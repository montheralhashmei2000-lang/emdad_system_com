import 'dart:io';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';

import '../db/app_database.dart';
import '../repos/catalog_repo.dart';
import '../repos/settings_repo.dart';

/// استيراد البيانات من ملفات Excel — بديل `excel-resume.js` في نسخة الويب.
///
/// • يتعرّف على الورقة من عناوين أعمدتها، فلا يشترط ترتيبًا معينًا.
/// • الاستيراد **قابل للاستئناف**: يحفظ موضع آخر صف نجح لكل ملف، فإن انقطع
///   العمل استُكمل من حيث توقف بدل إعادة كل شيء.
/// • التكرار آمن: الصنف يُحدَّث بكوده لا يُضاف مرتين.
class ExcelImportResult {
  ExcelImportResult();

  final Map<String, int> imported = {};
  final List<String> warnings = [];
  int skipped = 0;
  bool completed = true;

  int get total => imported.values.fold(0, (a, b) => a + b);

  @override
  String toString() => imported.isEmpty
      ? 'لم يُستورد أي صف — تحقق من عناوين الأعمدة'
      : 'استُورد $total صفًا: ${imported.entries.map((e) => '${e.key}=${e.value}').join('، ')}'
          '${skipped > 0 ? ' · تُخطّي $skipped صفًا ناقصًا' : ''}';
}

/// نوع الورقة المكتشَف من عناوينها.
enum SheetKind { items, suppliers, warehouses, units, opening, entitlements, unknown }

class ExcelImporter {
  ExcelImporter(this.db);

  final AppDatabase db;

  /// عدد الصفوف التي تُكتب قبل حفظ موضع الاستئناف.
  static const int chunkSize = 200;

  /// مرادفات عناوين الأعمدة بالعربية والإنجليزية.
  static const Map<String, List<String>> _aliases = {
    'code': ['الكود', 'كود', 'رمز', 'code', 'item code'],
    'name': ['الاسم', 'اسم الصنف', 'الصنف', 'name', 'item'],
    'category': ['التصنيف', 'الفئة', 'category'],
    'baseUnit': ['وحدة الأساس', 'الوحدة الأساسية', 'الوحدة', 'base unit', 'unit'],
    'unit2': ['الوحدة الكبرى', 'وحدة ثانية', 'الوحدة الثانوية', 'unit2'],
    'factor2': ['معامل التحويل', 'المعامل', 'factor', 'factor2'],
    'min': ['حد التنبيه', 'الحد الأدنى', 'min', 'min qty'],
    'barcode': ['الباركود', 'barcode'],
    'phone': ['الهاتف', 'الجوال', 'phone'],
    'notes': ['ملاحظات', 'notes'],
    'warehouse': ['المستودع', 'المخزن', 'warehouse', 'store'],
    'manager': ['أمين المستودع', 'المسؤول', 'manager'],
    'location': ['الموقع', 'location'],
    'qty': ['الكمية', 'الرصيد', 'qty', 'quantity', 'balance'],
    'parent': ['المعسكر', 'تابع لـ', 'parent', 'camp'],
    'type': ['النوع', 'type'],
    'qtyPerPerson': ['الكمية الشهرية', 'للفرد', 'نصيب الفرد', 'qty per person', 'monthly'],
  };

  static String _norm(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ');

  /// يبني خريطة: اسم الحقل ← رقم العمود، من صف العناوين.
  static Map<String, int> _headerMap(List<Data?> header) {
    final map = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final text = _norm(_cellText(header[i]));
      if (text.isEmpty) continue;
      _aliases.forEach((field, names) {
        if (map.containsKey(field)) return;
        if (names.any((n) => _norm(n) == text)) map[field] = i;
      });
    }
    return map;
  }

  static SheetKind _kindOf(Map<String, int> h) {
    if (h.containsKey('qtyPerPerson')) return SheetKind.entitlements;
    if (h.containsKey('qty') && h.containsKey('warehouse')) return SheetKind.opening;
    if (h.containsKey('baseUnit') || h.containsKey('unit2') || h.containsKey('min')) {
      return SheetKind.items;
    }
    if (h.containsKey('manager') || h.containsKey('location')) return SheetKind.warehouses;
    if (h.containsKey('parent') || h.containsKey('type')) return SheetKind.units;
    if (h.containsKey('phone')) return SheetKind.suppliers;
    if (h.containsKey('name') && h.containsKey('code')) return SheetKind.items;
    return SheetKind.unknown;
  }

  static String _cellText(Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
    }
    return v.toString();
  }

  static double _cellNum(Data? cell) {
    final v = cell?.value;
    if (v is IntCellValue) return v.value.toDouble();
    if (v is DoubleCellValue) return v.value;
    return double.tryParse(_cellText(cell).replaceAll(',', '')) ?? 0;
  }

  String _get(List<Data?> row, Map<String, int> h, String field) {
    final i = h[field];
    if (i == null || i >= row.length) return '';
    return _cellText(row[i]).trim();
  }

  double _getNum(List<Data?> row, Map<String, int> h, String field) {
    final i = h[field];
    if (i == null || i >= row.length) return 0;
    return _cellNum(row[i]);
  }

  /// مفتاح استئناف الملف: يعتمد المسار وحجمه حتى لا يُخلط بملف آخر.
  static String _resumeKey(File file) =>
      '${file.path}|${file.statSync().size}|${file.statSync().modified.millisecondsSinceEpoch}';

  Future<int> _resumePoint(File file, String sheet) async {
    final saved = await SettingsRepo(db).read('excelImport');
    if (saved['key'] != _resumeKey(file)) return 0;
    final rows = saved['rows'];
    if (rows is Map && rows[sheet] is num) return (rows[sheet] as num).toInt();
    return 0;
  }

  Future<void> _saveResume(File file, String sheet, int rowIndex) async {
    final repo = SettingsRepo(db);
    final saved = await repo.read('excelImport');
    final key = _resumeKey(file);
    final rows = <String, dynamic>{
      if (saved['key'] == key && saved['rows'] is Map) ...Map<String, dynamic>.from(saved['rows'] as Map),
      sheet: rowIndex,
    };
    await repo.write('excelImport', {'key': key, 'rows': rows});
  }

  Future<void> clearResume() => SettingsRepo(db).write('excelImport', {});

  /// يستورد كل أوراق الملف، ويستأنف ما انقطع منها.
  Future<ExcelImportResult> importFile(
    File file, {
    bool restart = false,
    void Function(String sheet, int done, int total)? onProgress,
  }) async {
    final res = ExcelImportResult();
    final book = Excel.decodeBytes(await file.readAsBytes());
    if (restart) await clearResume();

    for (final sheetName in book.tables.keys) {
      final sheet = book.tables[sheetName];
      if (sheet == null || sheet.rows.length < 2) continue;

      final header = _headerMap(sheet.rows.first);
      final kind = _kindOf(header);
      if (kind == SheetKind.unknown) {
        res.warnings.add('ورقة «$sheetName» تُخطّت — لم تُعرَف أعمدتها');
        continue;
      }

      final start = await _resumePoint(file, sheetName);
      final rows = sheet.rows;
      var done = 0;

      for (var r = start == 0 ? 1 : start; r < rows.length; r++) {
        final ok = await _importRow(kind, rows[r], header, res);
        if (!ok) res.skipped++;
        done++;
        if (done % chunkSize == 0) {
          await _saveResume(file, sheetName, r + 1);
          onProgress?.call(sheetName, r, rows.length - 1);
        }
      }
      await _saveResume(file, sheetName, rows.length);
      onProgress?.call(sheetName, rows.length - 1, rows.length - 1);
    }

    await clearResume();
    return res;
  }

  Future<bool> _importRow(
    SheetKind kind,
    List<Data?> row,
    Map<String, int> h,
    ExcelImportResult res,
  ) async {
    final catalog = CatalogRepo(db);
    switch (kind) {
      case SheetKind.items:
        final name = _get(row, h, 'name');
        if (name.isEmpty) return false;
        final code = _get(row, h, 'code');
        final baseUnit = _get(row, h, 'baseUnit');
        final unit2 = _get(row, h, 'unit2');
        final factor2 = _getNum(row, h, 'factor2');
        final existing = (await catalog.items())
            .where((i) => code.isNotEmpty ? i.code == code : i.name == name)
            .toList();
        final units = <ItemUnit>[
          if (baseUnit.isNotEmpty) ItemUnit(name: baseUnit, factor: 1, isBase: true),
          if (unit2.isNotEmpty && factor2 > 0) ItemUnit(name: unit2, factor: factor2),
        ];
        final categoryName = _get(row, h, 'category');
        var categoryId = '';
        if (categoryName.isNotEmpty) {
          final cats = await catalog.categories();
          final found = cats.where((c) => c.name == categoryName).toList();
          categoryId = found.isNotEmpty
              ? found.first.id
              : await catalog.saveCategory(name: categoryName);
        }
        await catalog.saveItem(
          id: existing.isNotEmpty ? existing.first.id : null,
          code: code,
          name: name,
          categoryId: categoryId,
          categoryName: categoryName,
          baseUnit: baseUnit.isEmpty ? 'وحدة' : baseUnit,
          units: units.isEmpty
              ? [const ItemUnit(name: 'وحدة', factor: 1, isBase: true)]
              : units,
          minQty: _getNum(row, h, 'min'),
          barcode: _get(row, h, 'barcode'),
        );
        res.imported['الأصناف'] = (res.imported['الأصناف'] ?? 0) + 1;
        return true;

      case SheetKind.suppliers:
        final name = _get(row, h, 'name');
        if (name.isEmpty) return false;
        final existing = (await catalog.suppliers()).where((s) => s.name == name).toList();
        await catalog.saveSupplier(
          id: existing.isNotEmpty ? existing.first.id : null,
          name: name,
          phone: _get(row, h, 'phone'),
          notes: _get(row, h, 'notes'),
        );
        res.imported['الموردون'] = (res.imported['الموردون'] ?? 0) + 1;
        return true;

      case SheetKind.warehouses:
        final name = _get(row, h, 'name').isEmpty ? _get(row, h, 'warehouse') : _get(row, h, 'name');
        if (name.isEmpty) return false;
        final existing = (await catalog.warehouses()).where((w) => w.name == name).toList();
        await catalog.saveWarehouse(
          id: existing.isNotEmpty ? existing.first.id : null,
          code: _get(row, h, 'code'),
          name: name,
          manager: _get(row, h, 'manager'),
          location: _get(row, h, 'location'),
          feedsAllCamps: true,
          campIds: const [],
          notes: _get(row, h, 'notes'),
        );
        res.imported['المستودعات'] = (res.imported['المستودعات'] ?? 0) + 1;
        return true;

      case SheetKind.units:
        final name = _get(row, h, 'name');
        if (name.isEmpty) return false;
        final all = await catalog.units();
        final existing = all.where((u) => u.name == name).toList();
        final parentName = _get(row, h, 'parent');
        final parent = all.where((u) => u.name == parentName).toList();
        final typeText = _norm(_get(row, h, 'type'));
        final isCamp = parentName.isEmpty || typeText.contains('معسكر') || typeText == 'camp';
        await catalog.saveUnit(
          id: existing.isNotEmpty ? existing.first.id : null,
          code: _get(row, h, 'code'),
          name: name,
          type: isCamp ? 'camp' : 'unit',
          parentId: parent.isNotEmpty ? parent.first.id : '',
          parentName: parent.isNotEmpty ? parent.first.name : '',
        );
        res.imported['الوحدات'] = (res.imported['الوحدات'] ?? 0) + 1;
        return true;

      case SheetKind.opening:
        final warehouse = _get(row, h, 'warehouse');
        final qty = _getNum(row, h, 'qty');
        if (warehouse.isEmpty || qty == 0) return false;
        final code = _get(row, h, 'code');
        final name = _get(row, h, 'name');
        final item = (await catalog.items())
            .where((i) => code.isNotEmpty ? i.code == code : i.name == name)
            .toList();
        if (item.isEmpty) {
          res.warnings.add('الرصيد الافتتاحي: لا يوجد صنف بالكود «$code» أو الاسم «$name»');
          return false;
        }
        await db.into(db.openingBalances).insertOnConflictUpdate(
              OpeningBalancesCompanion.insert(
                id: 'opb-xls-${item.first.id}-$warehouse',
                itemId: item.first.id,
                itemCode: Value(item.first.code),
                itemName: Value(item.first.name),
                warehouse: Value(warehouse),
                qty: Value(qty),
                date: Value(_today()),
                setBy: const Value('excel'),
              ),
            );
        res.imported['الأرصدة الافتتاحية'] = (res.imported['الأرصدة الافتتاحية'] ?? 0) + 1;
        return true;

      case SheetKind.entitlements:
        final qtyPerPerson = _getNum(row, h, 'qtyPerPerson');
        if (qtyPerPerson <= 0) return false;
        final code = _get(row, h, 'code');
        final name = _get(row, h, 'name');
        final items = await catalog.items();
        final item = items
            .where((i) => code.isNotEmpty ? i.code == code : i.name == name)
            .toList();
        if (item.isEmpty) {
          res.warnings.add('نسب الاستحقاق: لا يوجد صنف بالكود «$code» أو الاسم «$name»');
          return false;
        }
        final unitName = _get(row, h, 'baseUnit');
        final units = catalog.unitsOf(item.first);
        final unit = units.where((u) => u.name == unitName).toList();
        await db.into(db.entitlements).insertOnConflictUpdate(EntitlementsCompanion.insert(
              itemId: item.first.id,
              itemName: Value(item.first.name),
              qtyPerPerson: Value(qtyPerPerson),
              measureUnitName: Value(unit.isNotEmpty ? unit.first.name : item.first.baseUnit),
              measureFactor: Value(unit.isNotEmpty ? unit.first.factor : 1),
              updatedAt: Value(DateTime.now()),
            ));
        res.imported['نسب الاستحقاق'] = (res.imported['نسب الاستحقاق'] ?? 0) + 1;
        return true;

      case SheetKind.unknown:
        return false;
    }
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// قالب فارغ يوضح الأعمدة المتوقعة لكل ورقة.
  static List<int> template() {
    final book = Excel.createExcel();
    final def = book.getDefaultSheet();

    void sheet(String name, List<String> headers, List<List<String>> sample) {
      final s = book[name];
      s.appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
      for (final row in sample) {
        s.appendRow(row.map<CellValue?>(TextCellValue.new).toList());
      }
    }

    sheet('الأصناف',
        ['الكود', 'الاسم', 'التصنيف', 'وحدة الأساس', 'الوحدة الكبرى', 'معامل التحويل', 'حد التنبيه'],
        [
          ['1001', 'أرز أبيض', 'حبوب', 'كجم', 'كيس', '40', '200'],
        ]);
    sheet('الموردون', ['الاسم', 'الهاتف', 'ملاحظات'], [
      ['مؤسسة التموين', '777000000', ''],
    ]);
    sheet('المستودعات', ['الكود', 'الاسم', 'أمين المستودع', 'الموقع'], [
      ['W1', 'المخزن الرئيسي', '', 'المقر'],
    ]);
    sheet('الوحدات', ['الكود', 'الاسم', 'النوع', 'المعسكر'], [
      ['C1', 'معسكر الوحدة', 'معسكر', ''],
      ['U1', 'الكتيبة الأولى', 'وحدة', 'معسكر الوحدة'],
    ]);
    sheet('الأرصدة الافتتاحية', ['الكود', 'الاسم', 'المستودع', 'الكمية'], [
      ['1001', 'أرز أبيض', 'المخزن الرئيسي', '5000'],
    ]);
    sheet('نسب الاستحقاق', ['الكود', 'الاسم', 'الكمية الشهرية', 'وحدة الأساس'], [
      ['1001', 'أرز أبيض', '3', 'كجم'],
    ]);

    if (def != null) book.delete(def);
    return book.encode() ?? const [];
  }
}
