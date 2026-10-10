import 'dart:convert';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../security/auth_service.dart';
import '../security/perm.dart';
import 'imd_files.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// إعداد أدوات الجدول لكل شاشة — نفس `PM` و`IMP` في forms-ux.js:
/// p طباعة، x تصدير Excel. الافتراضي يُعدَّل من الإعدادات ويُحفظ على الجهاز (imdad.toolbarCfg).
class ImdToolbarMeta {
  const ImdToolbarMeta(this.label, this.group, {this.table = false, this.p = false, this.x = false, this.doc = false, this.own = false});
  final String label;
  final String group;
  final bool table; // meta.t: للشاشة جدول قابل للطباعة/التصدير
  final bool p;
  final bool x;
  final bool doc;
  final bool own;
}

class ImdToolbarCfg {
  static const key = 'imdad.toolbarCfg';

  static const pages = <String, ImdToolbarMeta>{
    'items': ImdToolbarMeta('الأصناف', 'البيانات الأساسية', table: true, x: true),
    'units': ImdToolbarMeta('الوحدات المستفيدة', 'البيانات الأساسية'),
    'suppliers': ImdToolbarMeta('الموردون', 'البيانات الأساسية', table: true),
    'stores': ImdToolbarMeta('المستودعات', 'البيانات الأساسية', table: true),
    'kitchens': ImdToolbarMeta('المطابخ والأفران', 'البيانات الأساسية'),
    'receive': ImdToolbarMeta('الاستلام (الواردات)', 'العمليات المخزنية', doc: true),
    'issue': ImdToolbarMeta('الصرف', 'العمليات المخزنية', doc: true),
    'transfer': ImdToolbarMeta('التحويل المخزني', 'العمليات المخزنية', doc: true),
    'returns': ImdToolbarMeta('المرتجعات', 'العمليات المخزنية', doc: true),
    'pendingOrders': ImdToolbarMeta('أوامر التوريد', 'العمليات المخزنية'),
    'feeding': ImdToolbarMeta('التفريدة اليومية', 'التشغيل اليومي', own: true),
    'kitchenLog': ImdToolbarMeta('سجل التشغيل', 'التشغيل اليومي'),
    'ratios': ImdToolbarMeta('نسب الاستحقاق', 'التشغيل اليومي', table: true, own: true),
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
  static Future<({bool p, bool x})> of(String page) async {
    final m = pages[page];
    if (m == null) return (p: false, x: false);
    final o = ((await overrides())[page] as Map?) ?? const {};
    bool v(String k, bool def) => o.containsKey(k) ? o[k] == true : def;
    return (p: m.table && v('p', m.p), x: m.table && v('x', m.x));
  }
}

/// `#imdTbar` — شريط الأدوات فوق الجدول.
class ImdTableToolbar extends StatefulWidget {
  const ImdTableToolbar({
    super.key,
    required this.page,
    this.onPrint,
    this.onExport,
  });

  final String page;
  final VoidCallback? onPrint;
  final VoidCallback? onExport;

  @override
  State<ImdTableToolbar> createState() => _ImdTableToolbarState();
}

class _ImdTableToolbarState extends State<ImdTableToolbar> {
  ({bool p, bool x})? _cfg;

  @override
  void initState() {
    super.initState();
    ImdToolbarCfg.of(widget.page).then((v) {
      if (mounted) setState(() => _cfg = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    if (cfg == null) return const SizedBox.shrink();
    // أدوات الشاشة تخضع لصلاحيات المستخدم: طباعة / تصدير / (استيراد = إضافة).
    // بلا مزوّد مصادقة (الاختبارات المعزولة) لا تُقيَّد.
    AuthService? auth;
    try {
      auth = context.read<AuthService>();
    } on ProviderNotFoundException {
      auth = null;
    }
    final perm = auth == null ? null : Perm(auth);
    bool allowed(String action) => perm == null || perm.has(widget.page, action);
    final t = (p: cfg.p && allowed('print'), x: cfg.x && allowed('export'));
    if (!t.p && !t.x) return const SizedBox.shrink();
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 10),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.toolbarFill,
        border: Border.all(color: c.toolbarLine),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (t.p) ImdButton(label: 'طباعة / PDF', icon: 'printer', small: true, onPressed: widget.onPrint),
          if (t.x) ImdButton.outline(label: 'تصدير Excel', icon: 'chart', small: true, onPressed: widget.onExport),
        ],
      ),
    );
  }
}

/// تصدير Excel بورقة واحدة «Sheet1». الاستيراد انتقل إلى قوالب `ExcelTemplates`.
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
}
