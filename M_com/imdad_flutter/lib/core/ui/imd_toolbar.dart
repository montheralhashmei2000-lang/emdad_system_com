import 'dart:convert';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'imd_files.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// إعداد أدوات الجدول لكل شاشة — نفس `PM` و`IMP` في forms-ux.js:
/// p طباعة، x تصدير Excel، i استيراد + قالب. الافتراضي يُعدَّل من الإعدادات ويُحفظ على الجهاز (imdad.toolbarCfg).
class ImdToolbarMeta {
  const ImdToolbarMeta(this.label, this.group, {this.table = false, this.p = false, this.x = false, this.i = false, this.doc = false, this.own = false});
  final String label;
  final String group;
  final bool table; // meta.t: للشاشة جدول قابل للطباعة/التصدير
  final bool p;
  final bool x;
  final bool i; // يدعم الاستيراد (IMP)
  final bool doc;
  final bool own;
}

class ImdToolbarCfg {
  static const key = 'imdad.toolbarCfg';

  static const pages = <String, ImdToolbarMeta>{
    'items': ImdToolbarMeta('الأصناف', 'البيانات الأساسية', table: true, x: true, i: true),
    'units': ImdToolbarMeta('الوحدات المستفيدة', 'البيانات الأساسية'),
    'suppliers': ImdToolbarMeta('الموردون', 'البيانات الأساسية', table: true),
    'stores': ImdToolbarMeta('المستودعات', 'البيانات الأساسية', table: true),
    'kitchens': ImdToolbarMeta('المطابخ والأفران', 'البيانات الأساسية'),
    'receive': ImdToolbarMeta('الاستلام (الواردات)', 'العمليات المخزنية', doc: true),
    'issue': ImdToolbarMeta('الصرف', 'العمليات المخزنية', doc: true),
    'transfer': ImdToolbarMeta('التحويل المخزني', 'العمليات المخزنية', doc: true),
    'returns': ImdToolbarMeta('المرتجعات', 'العمليات المخزنية', doc: true),
    'pendingOrders': ImdToolbarMeta('أوامر التوريد', 'العمليات المخزنية'),
    'feeding': ImdToolbarMeta('التغذية اليومية', 'التشغيل اليومي', i: true, own: true),
    'kitchenLog': ImdToolbarMeta('سجل التشغيل', 'التشغيل اليومي'),
    'ratios': ImdToolbarMeta('نسب الاستهلاك', 'التشغيل اليومي', table: true, i: true, own: true),
    'balances': ImdToolbarMeta('الأرصدة الحالية', 'التقارير والجرد', table: true, own: true),
    'stocktake': ImdToolbarMeta('جرد المخزون', 'التقارير والجرد', own: true),
    'auditTrail': ImdToolbarMeta('سجل النشاط والتدقيق', 'التقارير والجرد', table: true, x: true),
  };

  static Future<Map<String, dynamic>> overrides() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (jsonDecode(prefs.getString(key) ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Future<void> set(String page, String flag, bool on) async {
    final all = await overrides();
    final m = ((all[page] as Map?) ?? {}).cast<String, dynamic>();
    m[flag] = on;
    all[page] = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(all));
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// `tbFor(page)`
  static Future<({bool p, bool x, bool i})> of(String page) async {
    final m = pages[page];
    if (m == null) return (p: false, x: false, i: false);
    final o = ((await overrides())[page] as Map?) ?? const {};
    bool v(String k, bool def) => o.containsKey(k) ? o[k] == true : def;
    return (p: m.table && v('p', m.p), x: m.table && v('x', m.x), i: m.i && v('i', m.i));
  }
}

/// `#imdTbar` — شريط الأدوات فوق الجدول.
class ImdTableToolbar extends StatefulWidget {
  const ImdTableToolbar({
    super.key,
    required this.page,
    this.onPrint,
    this.onExport,
    this.onTemplate,
    this.onImport,
  });

  final String page;
  final VoidCallback? onPrint;
  final VoidCallback? onExport;
  final VoidCallback? onTemplate;
  final VoidCallback? onImport;

  @override
  State<ImdTableToolbar> createState() => _ImdTableToolbarState();
}

class _ImdTableToolbarState extends State<ImdTableToolbar> {
  ({bool p, bool x, bool i})? _cfg;

  @override
  void initState() {
    super.initState();
    ImdToolbarCfg.of(widget.page).then((v) {
      if (mounted) setState(() => _cfg = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _cfg;
    if (t == null || (!t.p && !t.x && !t.i)) return const SizedBox.shrink();
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.isDark ? c.surface : const Color(0xFFF2F7F5),
        border: Border.all(color: c.isDark ? c.line : const Color(0xFFDFE9E4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (t.p) ImdButton(label: 'طباعة / PDF', icon: 'printer', small: true, onPressed: widget.onPrint),
          if (t.x) ImdButton.outline(label: 'تصدير Excel', icon: 'chart', small: true, onPressed: widget.onExport),
          if (t.i) ImdButton.outline(label: 'قالب Excel', icon: 'arrow-down', small: true, onPressed: widget.onTemplate),
          if (t.i) ImdButton(label: 'استيراد Excel', icon: 'arrow-up', small: true, onPressed: widget.onImport),
        ],
      ),
    );
  }
}

/// Excel كما في forms-ux.js (SheetJS): تصدير ورقة واحدة «Sheet1»، وقراءة الصفوف كخرائط برؤوس الصف الأول.
class ImdExcel {
  static List<int> build(List<String> headers, List<List<String>> rows) {
    final book = Excel.createExcel();
    final def = book.getDefaultSheet();
    final sheet = book['Sheet1'];
    sheet.appendRow(headers.map<CellValue?>(TextCellValue.new).toList());
    for (final r in rows) {
      sheet.appendRow(r.map<CellValue?>(TextCellValue.new).toList());
    }
    if (def != null && def != 'Sheet1') book.delete(def);
    return book.encode() ?? const [];
  }

  /// `jsonToXLSX(headers, rows, fn)` / `tableXLSX(tbl, fn)`
  static Future<void> save(BuildContext context, String fileName, List<String> headers, List<List<String>> rows) async {
    await ImdFiles.saveBytes(context, '$fileName.xlsx', build(headers, rows));
  }

  /// `readXLSX` + `sheet_to_json({defval:''})`
  static List<Map<String, String>> read(List<int> bytes) {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) return const [];
    final sheet = book.tables[book.tables.keys.first]!;
    if (sheet.rows.isEmpty) return const [];
    String cell(Data? d) {
      final v = d?.value;
      if (v == null) return '';
      if (v is TextCellValue) return v.value.text ?? '';
      if (v is IntCellValue) return v.value.toString();
      if (v is DoubleCellValue) {
        final x = v.value;
        return x == x.roundToDouble() ? x.toInt().toString() : x.toString();
      }
      return v.toString();
    }

    final headers = sheet.rows.first.map(cell).toList();
    final out = <Map<String, String>>[];
    for (final row in sheet.rows.skip(1)) {
      if (row.every((c) => cell(c).isEmpty)) continue;
      out.add({for (var i = 0; i < headers.length; i++) headers[i]: i < row.length ? cell(row[i]) : ''});
    }
    return out;
  }

  /// اختيار ملف وقراءته (`filePick('.xlsx,.xls,.csv')`).
  static Future<List<Map<String, String>>?> pickAndRead(BuildContext context) async {
    final f = await ImdFiles.pick();
    if (f == null) return null;
    try {
      if (f.$1.toLowerCase().endsWith('.csv')) return _csv(utf8.decode(f.$2, allowMalformed: true));
      return read(f.$2);
    } catch (e) {
      if (context.mounted) showImdToast(context, '✖ تعذر قراءة الملف: $e');
      return null;
    }
  }

  static List<Map<String, String>> _csv(String text) {
    final lines = text.replaceFirst('﻿', '').split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];
    List<String> split(String l) {
      final out = <String>[];
      final b = StringBuffer();
      var q = false;
      for (var i = 0; i < l.length; i++) {
        final ch = l[i];
        if (ch == '"') {
          if (q && i + 1 < l.length && l[i + 1] == '"') {
            b.write('"');
            i++;
          } else {
            q = !q;
          }
        } else if (ch == ',' && !q) {
          out.add(b.toString());
          b.clear();
        } else {
          b.write(ch);
        }
      }
      out.add(b.toString());
      return out;
    }

    final h = split(lines.first);
    return [
      for (final l in lines.skip(1))
        () {
          final v = split(l);
          return {for (var i = 0; i < h.length; i++) h[i]: i < v.length ? v[i] : ''};
        }(),
    ];
  }
}
