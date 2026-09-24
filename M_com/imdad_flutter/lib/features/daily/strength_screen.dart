import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/catalog_repo.dart';
import '../../data/repos/daily_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../inventory/doc_kit.dart';

/// التفريدة اليومية — نقل `renderTafreeda()`:
/// تبويبان (تسجيل التفريدة / أرشيف التفريدات)، وطريقتا إدخال لا تُجمعان:
/// تفصيل قوة الوحدات (مجموعها = قوة المعسكر) أو إجمالي قوة المعسكر.
/// نسبة الزيادة تُدخل مرة واحدة وتُطبَّق على الطريقة المختارة.
class StrengthScreen extends StatefulWidget {
  const StrengthScreen({super.key});

  @override
  State<StrengthScreen> createState() => _StrengthScreenState();
}

/// صف أرشيف مجمّع بـ (المعسكر + التاريخ).
class _ArchRow {
  const _ArchRow({
    required this.campId,
    required this.campName,
    required this.date,
    required this.units,
    required this.camp,
    required this.base,
    required this.inc,
    required this.total,
  });

  final String campId;
  final String campName;
  final String date;
  final int units;

  /// تفريدة أُدخلت بطريقة «إجمالي المعسكر».
  final bool camp;
  final double base;
  final double inc;
  final double total;

  String get key => '$campId|$date';
}

class _StrengthScreenState extends State<StrengthScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepo _catalog = CatalogRepo(_db);
  late final DailyRepo _daily = DailyRepo(_db);
  late final Perm _perm = Perm.of(context);

  // النموذج
  final _pct = TextEditingController(text: '0');
  final _campBase = TextEditingController(text: '0');
  final Map<String, TextEditingController> _inputs = {};

  // الأرشيف
  final _archCamp = TextEditingController();
  String _archDate = '';

  String _tab = 'form';
  List<BeneficiaryUnit> _units = const [];
  List<Strength> _archive = const [];
  String _date = imdToday();
  String _campId = '';

  /// units = تفصيل الوحدات، camp = إجمالي المعسكر.
  String _mode = 'units';

  /// التفريدة محفوظة مسبقًا لهذا اليوم ⇒ وضع التعديل.
  bool _exists = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pct.dispose();
    _campBase.dispose();
    _archCamp.dispose();
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _writable => _perm.admin || _perm.manage('feeding');

  /// `tfCamps()`
  List<BeneficiaryUnit> get _camps => _units.where((u) => u.isCamp || u.type == 'camp').toList();

  /// `tfSubs(cid)`
  List<BeneficiaryUnit> _subs(String campId) =>
      _units.where((u) => u.parentId == campId && u.id != campId).toList();

  BeneficiaryUnit? get _camp {
    for (final c in _camps) {
      if (c.id == _campId) return c;
    }
    return null;
  }

  /// `tfFetch()`
  Future<void> _load() async {
    final units = await _catalog.units();
    final archive = await _daily.strengths();
    if (!mounted) return;
    setState(() {
      _units = units;
      _archive = archive;
      _loading = false;
    });
    if (_campId.isEmpty && _camps.length == 1) {
      _campId = _camps.first.id;
      await _loadRows();
    }
  }

  /// `tfRecordsFor(cid, date)` + `tfFill(...)`
  Future<void> _loadRows() async {
    if (_campId.isEmpty) {
      setState(() => _exists = false);
      return;
    }
    final recs = await _daily.strengths(date: _date, campId: _campId);
    final subs = _subs(_campId);

    Strength? campRec;
    final byUnit = <String, Strength>{};
    for (final r in recs) {
      if (r.mode == 'camp' || r.unitId == _campId) {
        campRec = r;
      } else {
        byUnit[r.unitId] = r;
      }
    }

    if (recs.isNotEmpty) {
      final withPct = recs.where((r) => r.pct != 0).firstOrNull;
      double pct;
      if (withPct != null) {
        pct = withPct.pct;
      } else {
        final sb = recs.fold<double>(0, (a, v) => a + v.soldierCount);
        final si = recs.fold<double>(0, (a, v) => a + v.officerCount);
        pct = sb == 0 ? 0 : (si / sb * 10000).round() / 100;
      }
      imdSetText(_pct, _plain(pct));
    }
    imdSetText(_campBase, _plain(campRec?.soldierCount ?? 0));
    for (final u in subs) {
      imdSetText(_ctrl(u.id), _plain(byUnit[u.id]?.soldierCount ?? 0));
    }

    setState(() {
      _exists = recs.isNotEmpty;
      if (recs.isNotEmpty) {
        _mode = campRec != null ? 'camp' : 'units';
      } else if (subs.isEmpty) {
        _mode = 'camp';
      }
    });
  }

  TextEditingController _ctrl(String id) =>
      _inputs.putIfAbsent(id, () => TextEditingController(text: '0'));

  double get _pctValue => double.tryParse(_pct.text.trim()) ?? 0;
  double _num(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  /// `tfRecalc()` — الزيادة = round(الأساسي × النسبة ÷ 100).
  double _incOf(double base) => (base * _pctValue / 100).round().toDouble();

  (double base, double inc) get _totals {
    if (_mode == 'camp') {
      final b = _num(_campBase);
      return (b, _incOf(b));
    }
    var base = 0.0, inc = 0.0;
    for (final u in _subs(_campId)) {
      final b = _num(_ctrl(u.id));
      base += b;
      inc += _incOf(b);
    }
    return (base, inc);
  }

  /// `tfSetMode(m, fromUser)` — عند الانتقال إلى «إجمالي المعسكر» تُملأ القوة بمجموع الوحدات.
  void _setMode(String m) {
    if (m == 'camp' && _num(_campBase) == 0) {
      var s = 0.0;
      for (final u in _subs(_campId)) {
        s += _num(_ctrl(u.id));
      }
      imdSetText(_campBase, _plain(s));
    }
    setState(() => _mode = m);
  }

  /// `tfClone()` — أقرب تفريدة خلال 30 يومًا سابقة لنفس المعسكر.
  Future<void> _clone() async {
    if (_campId.isEmpty) {
      showImdToast(context, '✖ اختر المعسكر أولًا', error: true);
      return;
    }
    final from = DateTime.tryParse(_date) ?? DateTime.now();
    for (var i = 1; i <= 30; i++) {
      final ds = isoDay(from.subtract(Duration(days: i)));
      final recs = await _daily.strengths(date: ds, campId: _campId);
      if (recs.isEmpty) continue;
      final subs = _subs(_campId);
      final byUnit = <String, Strength>{};
      Strength? campRec;
      for (final r in recs) {
        if (r.mode == 'camp' || r.unitId == _campId) {
          campRec = r;
        } else {
          byUnit[r.unitId] = r;
        }
      }
      imdSetText(_pct, _plain(recs.first.pct));
      imdSetText(_campBase, _plain(campRec?.soldierCount ?? 0));
      for (final u in subs) {
        imdSetText(_ctrl(u.id), _plain(byUnit[u.id]?.soldierCount ?? 0));
      }
      if (!mounted) return;
      setState(() => _mode = campRec != null ? 'camp' : 'units');
      showImdToast(context, '📥 استُنسخت تفريدة $ds');
      return;
    }
    if (mounted) showImdToast(context, '⚠ لم يُعثر على تفريدة سابقة قريبة لهذا المعسكر');
  }

  /// `tfSave()`
  Future<void> _save() async {
    if (!_perm.guard(context, 'feeding', PermAction.edit)) return;
    if (_campId.isEmpty) {
      showImdToast(context, '✖ اختر المعسكر أولًا', error: true);
      return;
    }
    if (_date.isEmpty) {
      showImdToast(context, '✖ اختر التاريخ', error: true);
      return;
    }
    final pct = _pctValue;
    if (pct < 0) {
      showImdToast(context, '✖ نسبة الزيادة لا يمكن أن تكون سالبة', error: true);
      return;
    }
    final camp = _camp;
    final campName = camp?.name ?? '';
    final rows = <StrengthEntry>[];

    if (_mode == 'camp') {
      final base = _num(_campBase);
      if (base <= 0) {
        showImdToast(context, '✖ أدخل إجمالي القوة الفعلية للمعسكر', error: true);
        return;
      }
      rows.add(StrengthEntry(
        unitId: _campId,
        unitName: campName,
        campName: campName,
        soldierCount: base,
        officerCount: _incOf(base),
        pct: pct,
        mode: 'camp',
      ));
    } else {
      for (final u in _subs(_campId)) {
        final base = _num(_ctrl(u.id));
        if (base < 0) continue;
        rows.add(StrengthEntry(
          unitId: u.id,
          unitName: u.name,
          campName: campName,
          soldierCount: base,
          officerCount: _incOf(base),
          pct: pct,
        ));
      }
      if (!rows.any((r) => r.soldierCount > 0)) {
        showImdToast(
            context, '✖ أدخل القوة الفعلية للوحدات أولًا (أو اختر «إجمالي قوة المعسكر»)',
            error: true);
        return;
      }
    }

    await _daily.saveCampStrength(
      campId: _campId,
      date: _date,
      rows: rows,
      createdBy: _perm.email,
    );
    final total = rows.fold<double>(0, (a, r) => a + r.soldierCount + r.officerCount);
    if (!mounted) return;
    showImdToast(context, '🎉 حُفظت التفريدة — إجمالي المعسكر ${nf(total)} فرد');
    await _load();
    await _loadRows();
  }

  /// `tfPrintMilitary()` — استمارة التفريدة وحصر القوة اليومية.
  Future<void> _print() async {
    if (_campId.isEmpty) {
      showImdToast(context, '✖ اختر المعسكر أولًا', error: true);
      return;
    }
    final rows = <List<String>>[];
    final (base, inc) = _totals;
    if (_mode == 'camp') {
      rows.add(['1', 'إجمالي قوة المعسكر (بدون تفصيل الوحدات)', nf(base), nf(inc), nf(base + inc)]);
    } else {
      var i = 0;
      for (final u in _subs(_campId)) {
        final b = _num(_ctrl(u.id));
        rows.add([nf(++i), u.name, nf(b), nf(_incOf(b)), nf(b + _incOf(b))]);
      }
    }
    if (base + inc == 0) {
      showImdToast(context, '⚠ الجدول فارغ أو التفريدة صفرية');
      return;
    }
    final layout = await SettingsRepo(_db).printLayout();
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: 'استمارة التفريدة وحصر القوة اليومية',
        headers: const ['م', 'اسم الوحدة الفرعية', 'القوة الفعلية (الأساسي)', 'الزيادة', 'الإجمالي النهائي'],
        columnFlex: const [1, 6, 3, 2, 3],
        rows: rows,
        leftValues: {'date': _date},
        fieldValues: {
          'party': _camp?.name ?? '',
          'notes': 'نسبة الزيادة ${nf(_pctValue)}% — الإجمالي الكلي للمعسكر ${nf(base + inc)} فرد',
        },
      ),
      layout: layout,
    );
  }

  // ───────── الأرشيف ─────────
  /// `tfArchive()` — تجميع السجلات بـ (المعسكر + التاريخ).
  List<_ArchRow> _archRows() {
    final groups = <String, List<Strength>>{};
    for (final s in _archive) {
      groups.putIfAbsent('${s.campId}|${s.strengthDate}', () => []).add(s);
    }
    final out = groups.values.map((g) {
      final f = g.first;
      return _ArchRow(
        campId: f.campId,
        campName: f.campName.isNotEmpty ? f.campName : '—',
        date: f.strengthDate,
        units: g.length,
        camp: g.any((x) => x.mode == 'camp' || x.unitId == x.campId),
        base: g.fold<double>(0, (a, x) => a + x.soldierCount),
        inc: g.fold<double>(0, (a, x) => a + x.officerCount),
        total: g.fold<double>(0, (a, x) => a + (x.total != 0 ? x.total : x.soldierCount + x.officerCount)),
      );
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final q = _archCamp.text.trim().toLowerCase();
    return out.where((r) {
      if (q.isNotEmpty && !r.campName.toLowerCase().contains(q)) return false;
      if (_archDate.isNotEmpty && r.date != _archDate) return false;
      return true;
    }).toList();
  }

  /// `tfGoTo(r, edit)`
  Future<void> _goTo(_ArchRow r) async {
    setState(() {
      _tab = 'form';
      _campId = r.campId;
      _date = r.date;
    });
    await _loadRows();
  }

  Future<void> _deleteArch(_ArchRow r) async {
    if (!_perm.guard(context, 'feeding', PermAction.delete)) return;
    final ok = await imdConfirm(
      context,
      'حذف تفريدة «${r.campName}» بتاريخ ${r.date} بالكامل؟ لا يمكن التراجع.',
      ok: 'حذف',
      danger: true,
    );
    if (!ok) return;
    await _daily.deleteCampStrength(campId: r.campId, date: r.date);
    if (!mounted) return;
    showImdToast(context, '✔ حُذفت التفريدة');
    await _load();
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'التفريدة اليومية',
        icon: 'calendar',
        subtitle: 'حصر القوة اليومي بالمعسكرات + أرشيف التفريدات السابقة',
      ),
      ImdItabs(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: const [
          ImdTab('form', 'تسجيل التفريدة اليومية', icon: 'file'),
          ImdTab('arch', 'أرشيف التفريدات', icon: 'folder'),
        ],
      ),
      const SizedBox(height: 12),
      if (_loading)
        const ImdLd('⏳ جارٍ التحميل…')
      else if (_tab == 'form')
        _form()
      else
        _archiveView(),
    ]);
  }

  Widget _form() {
    final w = _writable;
    final camps = _camps;
    if (camps.isEmpty) {
      return const ImdICard(
        child: ImdLd('لا معسكرات بعد — أضفها من شاشة «الوحدات المستفيدة»'),
      );
    }
    final subs = _subs(_campId);
    final (base, inc) = _totals;

    return ImdICard(
      title: w ? 'تسجيل التفريدة اليومية' : 'عرض التفريدة (قراءة فقط)',
      icon: w ? 'file' : 'eye',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // `.tokbar`
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(
            width: 150,
            child: ImdLabeled(
              'التاريخ',
              ImdDateField(
                value: _date,
                onChanged: (v) async {
                  setState(() => _date = v);
                  await _loadRows();
                },
              ),
              size: 11,
            ),
          ),
          SizedBox(
            width: 260,
            child: ImdLabeled(
              'المعسكر الرئيسي *',
              ImdSelect<String>(
                hint: '— اختر المعسكر —',
                items: [for (final c in camps) (c.id, '${c.code} — ${c.name}')],
                value: _campId,
                onChanged: (v) async {
                  setState(() => _campId = v ?? '');
                  await _loadRows();
                },
              ),
              size: 11,
            ),
          ),
          SizedBox(
            width: 160,
            child: ImdLabeled(
              'نسبة الزيادة % (مرة واحدة)',
              ImdFld(
                controller: _pct,
                number: true,
                enabled: w,
                onChanged: (_) => setState(() {}),
              ),
              size: 11,
            ),
          ),
          if (w)
            ImdButton.outline(
              label: 'استنساخ تفريدة سابقة',
              icon: 'download',
              small: true,
              height: 44,
              onPressed: _clone,
            ),
        ]),
        const SizedBox(height: 12),
        // `.tf-mode`
        ImdGrid(columns: 2, minItemWidth: 280, gap: 10, children: [
          _modeCard('units', 'تفصيل قوة الوحدات الفرعية', 'يُحسب إجمالي المعسكر تلقائيًا', enabled: w),
          _modeCard('camp', 'إجمالي قوة المعسكر كاملًا', 'بدون تفصيل الوحدات', enabled: w),
        ]),
        if (_exists && w) ...[
          const SizedBox(height: 10),
          const ImdAlert('✏️ وضع التعديل الفعّال: جارٍ تحديث تفريدة موجودة', tone: ImdTone.info),
        ],
        const SizedBox(height: 10),
        if (_mode == 'camp')
          _trow('إجمالي قوة المعسكر', _campBase, enabled: w, icon: 'home')
        else if (_campId.isEmpty)
          const ImdLd('اختر المعسكر لعرض وحداته')
        else if (subs.isEmpty)
          const ImdLd('لا وحدات تابعة لهذا المعسكر — استخدم «إجمالي قوة المعسكر» '
              'أو أضف الوحدات من شاشة «الوحدات المستفيدة»')
        else
          for (final u in subs) _trow(u.name, _ctrl(u.id), enabled: w),
        // `.tfoot`
        _tfoot(base + inc),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${_mode == 'camp' ? 'طريقة الإدخال: إجمالي المعسكر' : 'طريقة الإدخال: تفصيل الوحدات (المجموع تلقائي)'}'
            ' — القوة الفعلية ${nf(base)} + الزيادة ${nf(inc)} (${nf(_pctValue)}%)',
            style: TextStyle(fontSize: 12.5, color: context.imd.muted, height: 1.7),
          ),
        ),
        Row(children: [
          Expanded(
            child: ImdButton.outline(
              label: 'طباعة التفريدة العسكرية',
              icon: 'printer',
              expand: true,
              onPressed: _print,
            ),
          ),
          if (w) ...[
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ImdButton(
                label: _exists ? 'تحديث وحفظ التعديلات' : 'أضف جديد / حفظ',
                icon: 'save',
                expand: true,
                onPressed: _save,
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  /// `.tf-mode label` — خيار بحدّ ملوّن عند الاختيار.
  Widget _modeCard(String value, String label, String hint, {required bool enabled}) {
    final c = context.imd;
    final on = _mode == value;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => _setMode(value) : null,
        child: Container(
          constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: on ? c.accentSoft : c.surface,
            border: Border.all(color: on ? c.accent : c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            ImdIcon(on ? 'check-circle' : 'square', size: 17, color: on ? c.accent : c.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
                Text(hint, style: TextStyle(fontSize: 11.5, color: c.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// `.trow` + `.tgrid` — اسم الوحدة، القوة الفعلية، الزيادة (للقراءة)، الإجمالي.
  Widget _trow(String name, TextEditingController base, {required bool enabled, String icon = 'dot'}) {
    final c = context.imd;
    final b = _num(base);
    final inc = _incOf(b);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(builder: (context, cons) {
        final narrow = cons.maxWidth < 560;
        final fields = [
          SizedBox(
            width: narrow ? (cons.maxWidth - 8) / 2 : 110,
            child: ImdLabeled(
              'القوة الفعلية',
              ImdFld(controller: base, number: true, dense: true, enabled: enabled, onChanged: (_) => setState(() {})),
              size: 11,
            ),
          ),
          SizedBox(
            width: narrow ? (cons.maxWidth - 8) / 2 : 110,
            // `.tInc` — حقل محسوب للقراءة فقط بخلفية #EEF1EE كما في الويب.
            child: ImdLabeled('الزيادة', ImdReadonlyField(text: _plain(inc)), size: 11),
          ),
          Container(
            width: narrow ? cons.maxWidth : 90,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(nf(b + inc),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.accent)),
          ),
        ];
        return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: narrow ? cons.maxWidth : cons.maxWidth - 110 - 110 - 90 - 24,
            child: Row(children: [
              ImdIcon(icon, size: 14, color: c.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: c.text)),
              ),
            ]),
          ),
          ...fields,
        ]);
      }),
    );
  }

  /// `.tfoot` + `.tgrand` — شريط الإجمالي بخلفية ذهبية متقطعة.
  Widget _tfoot(double total) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.warnSoft,
        border: Border.all(color: c.warn, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Text('إجمالي قوة المعسكر:', style: TextStyle(fontSize: 14, color: c.warn, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Text(nf(total), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c.warn)),
      ]),
    );
  }

  /// `tfArchive()` + `tfPaintArch()`
  Widget _archiveView() {
    if (!_perm.has('feeding', PermAction.delete) && !_perm.admin) {
      return const ImdICard(child: ImdLd('لا تملك صلاحية إدارة الأرشيف'));
    }
    final rows = _archRows();
    final w = _writable;
    return ImdICard(
      title: 'أرشيف التفريدات',
      icon: 'folder',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(
            width: 150,
            child: ImdLabeled('من تاريخ',
                ImdDateField(value: _archDate, onChanged: (v) => setState(() => _archDate = v)),
                size: 11),
          ),
          SizedBox(
            width: 240,
            child: ImdLabeled(
              'المعسكر',
              ImdFld(
                controller: _archCamp,
                hint: 'بحث باسم المعسكر…',
                onChanged: (_) => setState(() {}),
              ),
              size: 11,
            ),
          ),
          ImdButton.outline(
            label: 'عرض الكل',
            icon: 'refresh',
            small: true,
            height: 44,
            onPressed: () => setState(() {
              _archDate = '';
              _archCamp.clear();
            }),
          ),
          ImdChip('عدد التفريدات: ${nf(rows.length)}', tone: ImdTone.code),
        ]),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const ImdLd('لا تفريدات مطابقة')
        else
          for (final r in rows) _archRowView(r, w),
      ]),
    );
  }

  /// `.archRow`
  Widget _archRowView(_ArchRow r, bool w) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ImdChip(r.date.isEmpty ? '—' : r.date, tone: ImdTone.code),
        Text(r.campName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
        ImdChip(r.camp ? 'إجمالي المعسكر' : '${nf(r.units)} وحدات', tone: ImdTone.off),
        ImdChip('أساسي ${nf(r.base)}', tone: ImdTone.ok),
        ImdChip('زيادات ${nf(r.inc)}', tone: ImdTone.pend),
        Text('الإجمالي ${nf(r.total)}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c.accent)),
        if (w) ...[
          ImdButton.outline(label: 'عرض', icon: 'eye', small: true, onPressed: () => _goTo(r)),
          ImdButton(label: 'تعديل', icon: 'edit', small: true, onPressed: () => _goTo(r)),
          ImdButton(
            label: 'حذف',
            icon: 'trash',
            small: true,
            kind: ImdBtnKind.danger,
            onPressed: () => _deleteArch(r),
          ),
        ],
      ]),
    );
  }

  static String _plain(double v) {
    final r = (v * 1000).round() / 1000;
    return r % 1 == 0 ? r.toInt().toString() : r.toString();
  }
}
