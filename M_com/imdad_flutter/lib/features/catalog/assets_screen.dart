import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/auth_service.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/assets_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/assets.dart';
import 'asset_barcode_sheet.dart';
import 'cylinders_view.dart';

/// الأصول الثابتة: المطابخ والأفران والمعدات وعهدها، وتبويب «الأسطوانات».
///
/// الأسطوانات ليست أصولًا بأرقام تسلسلية: تُعدّ بالكمية وتدور بين الامتلاء
/// والفراغ والمستودعات والعهد عبر سندات الحركة، فلها تبويب يعرض موقفها
/// المحسوب من تلك السندات ([CylindersView]) لا سجلٌّ يدوي ثانٍ.
///
/// بنية الشاشة كبقية شاشات التعريف (المستودعات، الأصناف): شريط بحث وإحصاءات،
/// ثم نموذج إلى جانب جدول. ولا `Scaffold` ولا `AppBar`: الشاشة تعيش داخل
/// [HomeShell] وتأخذ ترويستها منه، فإضافة شريط ثانٍ تُظهر ترويستين.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final AssetsRepo _repo = AssetsRepo(_db);

  List<Asset> _rows = const [];
  List<Facility> _facilities = const [];
  List<BeneficiaryUnit> _units = const [];
  List<Warehouse> _warehouses = const [];
  List<Supplier> _suppliers = const [];
  Map<String, AssetAssignment> _openAssignments = const {};

  final _q = TextEditingController();
  final _name = TextEditingController();
  final _serial = TextEditingController();
  final _value = TextEditingController();
  final _lifespan = TextEditingController();
  final _invoice = TextEditingController();
  final _notes = TextEditingController();

  String _type = AssetType.equipment;
  String _status = AssetStatus.isNew;
  String _acquired = '';
  String _facilityId = '';
  String _unitId = '';
  String _warehouse = '';
  String _supplierId = '';

  String _filterType = '';
  String _filterStatus = '';
  String? _editId;
  bool _loading = true;

  /// assets | cylinders
  String _tab = 'assets';

  static const _tabs = [
    ImdTab('assets', 'المعدات والأصول', icon: 'package'),
    ImdTab('cylinders', 'الأسطوانات', icon: 'database'),
  ];

  static const _title = ImdPageTitle(
    title: 'الأصول الثابتة',
    icon: 'package',
    subtitle: 'المطابخ والأفران والمعدات والآليات: اقتناؤها وعمرها الافتراضي وعهدها '
        'لدى الوحدات المستفيدة — وموقف الأسطوانات ممتلئةً وفارغةً وعهدةً',
  );

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    for (final c in [_q, _name, _serial, _value, _lifespan, _invoice, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _render() async {
    final scope = Perm.of(context).scope;
    final rows = await _repo.assets(type: _filterType, status: _filterStatus, scope: scope);
    final facilities = await _db.select(_db.facilities).get();
    final units = await _db.select(_db.beneficiaryUnits).get();
    final warehouses = await _db.select(_db.warehouses).get();
    final suppliers = await _db.select(_db.suppliers).get();

    // العهد القائمة تُقرأ دفعة واحدة: استعلامٌ لكل صف يجعل قائمة بمئة أصل
    // مئةَ رحلة إلى القاعدة عند كل إعادة رسم.
    final open = await (_db.select(_db.assetAssignments)
          ..where((t) => t.returnedDate.equals('')))
        .get();

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _facilities = facilities;
      _units = units;
      _warehouses = warehouses;
      _suppliers = suppliers;
      _openAssignments = {for (final g in open) g.assetId: g};
      _loading = false;
    });
  }

  void _loadForm(Asset? a) {
    imdSetText(_name, a?.name ?? '');
    imdSetText(_serial, a?.serialNumber ?? '');
    imdSetText(_value, a == null || a.value == 0 ? '' : '${a.value}');
    imdSetText(_lifespan, a == null || a.lifespanMonths == 0 ? '' : '${a.lifespanMonths}');
    imdSetText(_invoice, a?.invoiceNumber ?? '');
    imdSetText(_notes, a?.notes ?? '');
    setState(() {
      _editId = a?.id;
      _type = a?.assetType ?? AssetType.equipment;
      _status = a?.status ?? AssetStatus.isNew;
      _acquired = a?.acquisitionDate ?? '';
      _facilityId = a?.facilityId ?? '';
      _unitId = a?.beneficiaryUnitId ?? '';
      _warehouse = a?.warehouse ?? '';
      _supplierId = a?.supplierId ?? '';
    });
  }

  Future<void> _save() async {
    final perm = Perm.of(context);
    if (!perm.guard(context, 'assets', _editId == null ? PermAction.create : PermAction.edit)) {
      return;
    }
    for (final error in [
      AssetRules.validateName(_name.text),
      AssetRules.validateType(_type),
      AssetRules.validateValue(_value.text),
      AssetRules.validateLifespan(_lifespan.text),
      AssetRules.validateAcquisitionDate(_acquired),
      AssetRules.validatePlacement(
        facilityId: _facilityId,
        beneficiaryUnitId: _unitId,
        warehouse: _warehouse,
      ),
    ]) {
      if (error != null) {
        showImdToast(context, '✖ $error', error: true);
        return;
      }
    }
    if (_warehouse.isNotEmpty && !perm.canWh(_warehouse)) {
      showImdToast(context, Perm.scopeBlock(_warehouse), error: true);
      return;
    }
    if (await _repo.serialTaken(_serial.text, exceptId: _editId ?? '')) {
      if (mounted) showImdToast(context, '✖ الرقم التسلسلي مستعمل في أصل آخر', error: true);
      return;
    }
    if (!mounted) return;

    final facility = _facilities.where((f) => f.id == _facilityId).firstOrNull;
    final unit = _units.where((u) => u.id == _unitId).firstOrNull;
    final supplier = _suppliers.where((s) => s.id == _supplierId).firstOrNull;
    await _repo.save(
      id: _editId,
      name: _name.text,
      assetType: _type,
      serialNumber: _serial.text,
      facilityId: _facilityId,
      facilityName: facility?.name ?? '',
      beneficiaryUnitId: _unitId,
      beneficiaryUnitName: unit?.name ?? '',
      warehouse: _warehouse,
      status: _status,
      acquisitionDate: _acquired,
      value: double.tryParse(_value.text.trim()) ?? 0,
      lifespanMonths: int.tryParse(_lifespan.text.trim()) ?? 0,
      supplierId: _supplierId,
      supplierName: supplier?.name ?? '',
      invoiceNumber: _invoice.text.trim(),
      notes: _notes.text.trim(),
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, _editId == null ? '🎉 أُضيف الأصل' : '✔ حُدّث الأصل');
    _loadForm(null);
    await _render();
  }

  Future<void> _delete(Asset a) async {
    if (!Perm.of(context).guard(context, 'assets', PermAction.delete)) return;
    if (!await imdConfirm(context, 'حذف الأصل «${a.name}» وسجل عهده؟',
        ok: 'حذف', danger: true)) {
      return;
    }
    if (!mounted) return;
    final res = await _repo.delete(
      a.id,
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ حُذف الأصل' : '✖ ${res.error}', error: !res.ok);
    if (res.ok && _editId == a.id) _loadForm(null);
    await _render();
  }

  Future<void> _assign(Asset a) async {
    if (!Perm.of(context).guard(context, 'assets', PermAction.edit)) return;
    final open = _openAssignments[a.id];
    if (open != null) {
      if (!await imdConfirm(
        context,
        'استرجاع «${a.name}» من ${open.beneficiaryUnitName}؟',
        ok: 'استرجاع',
      )) {
        return;
      }
      if (!mounted) return;
      await _repo.returnAssignment(
        open.id,
        returnedDate: DateTime.now().toIso8601String().substring(0, 10),
        actor: context.read<AuthService>().currentUser?.email ?? '',
      );
      if (!mounted) return;
      showImdToast(context, '✔ استُرجع الأصل');
      await _render();
      return;
    }
    final unitId = await _pickUnit(a);
    if (unitId == null || !mounted) return;
    final unit = _units.where((u) => u.id == unitId).firstOrNull;
    final res = await _repo.assign(
      assetId: a.id,
      beneficiaryUnitId: unitId,
      beneficiaryUnitName: unit?.name ?? '',
      assignedDate: DateTime.now().toIso8601String().substring(0, 10),
      actor: context.read<AuthService>().currentUser?.email ?? '',
    );
    if (!mounted) return;
    showImdToast(context, res.ok ? '✔ سُلّم الأصل عهدةً' : '✖ ${res.error}', error: !res.ok);
    await _render();
  }

  /// مسح باركود أصل: يفتح بطاقته مباشرة.
  ///
  /// والبحث اليدوي متاح دائمًا في شريط البحث — الماسح غير مدعوم على ويندوز،
  /// وقارئ USB يكتب في الحقل نفسه كأنه لوحة مفاتيح.
  Future<void> _scan() async {
    final code = await ImdScanner.scan(context);
    if (code == null || code.isEmpty || !mounted) return;
    final found = await _repo.byBarcode(code);
    if (!mounted) return;
    if (found == null) {
      showImdToast(context, '✖ لا يوجد أصل بهذا الرمز: $code', error: true);
      return;
    }
    await showAssetBarcodeSheet(context, found);
    if (!mounted) return;
    _loadForm(found);
  }

  Future<String?> _pickUnit(Asset a) async {
    var chosen = _unitId.isNotEmpty ? _unitId : (_units.firstOrNull?.id ?? '');
    return showImdModal<String>(
      context,
      title: 'تسليم «${a.name}» عهدةً',
      icon: 'users',
      maxWidth: 420,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => ImdLabeled(
          'الوحدة المستفيدة',
          ImdSelect<String>(
            items: [for (final u in _units) (u.id, u.name)],
            value: chosen,
            onChanged: (v) => setS(() => chosen = v ?? ''),
          ),
        ),
      ),
      actions: (ctx) => [
        ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
        ImdButton(
          label: 'تسليم',
          icon: 'check',
          onPressed: () => Navigator.of(ctx).pop(chosen.isEmpty ? null : chosen),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ImdPillTabs<String>(value: _tab, onChanged: (t) => setState(() => _tab = t), tabs: _tabs);
    if (_tab == 'cylinders') {
      return ImdPage(children: [_title, tabs, const CylindersView()]);
    }
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'الأصول الثابتة', icon: 'package'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final perm = Perm.of(context);
    final can = perm.writable('assets');
    final q = _q.text.trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows
            .where((a) => [a.name, a.serialNumber, a.beneficiaryUnitName, a.facilityName]
                .any((v) => v.toLowerCase().contains(q)))
            .toList();

    final nearing = _rows.where((a) =>
        AssetRules.lifeOf(
          acquisitionDate: a.acquisitionDate,
          lifespanMonths: a.lifespanMonths,
        ) ==
        AssetLife.nearingEnd);
    final expired = _rows.where((a) =>
        AssetRules.lifeOf(
          acquisitionDate: a.acquisitionDate,
          lifespanMonths: a.lifespanMonths,
        ) ==
        AssetLife.expired);
    final totalValue = _rows.fold<double>(0, (s, a) => s + a.value);
    final cur = _rows.where((a) => a.id == _editId).firstOrNull;

    return ImdPage(children: [
      _title,
      tabs,
      ImdKpis(children: [
        ImdKpi(label: 'إجمالي الأصول', value: nf(_rows.length)),
        ImdKpi(
          label: 'في الخدمة',
          value: nf(_rows.where((a) => !AssetStatus.outOfService.contains(a.status)).length),
        ),
        ImdKpi(
          label: 'قارب عمرها الانتهاء',
          value: nf(nearing.length),
          extra: nearing.isEmpty ? null : const ImdChip('تنبيه', tone: ImdTone.pend),
        ),
        ImdKpi(
          label: 'انقضى عمرها',
          value: nf(expired.length),
          extra: expired.isEmpty ? null : const ImdChip('يلزم استبدال', tone: ImdTone.err),
        ),
        ImdKpi(label: 'القيمة الدفترية', value: nf(totalValue)),
      ]),
      ImdICard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdSearchBar(
            controller: _q,
            hint: 'بحث بالاسم أو الرقم التسلسلي أو الوحدة…',
            onChanged: (_) => setState(() {}),
            actions: [
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _render),
              if (ImdScanner.supported)
                ImdButton.outline(
                  label: 'مسح باركود',
                  icon: 'camera',
                  small: true,
                  onPressed: _scan,
                ),
              if (can)
                ImdButton.outline(
                  label: 'أصل جديد',
                  icon: 'plus-square',
                  small: true,
                  onPressed: () => _loadForm(null),
                ),
            ],
          ),
          ImdF2(children: [
            ImdLabeled(
              'تصفية بالنوع',
              ImdSelect<String>(
                items: [('', 'كل الأنواع'), for (final t in AssetType.all) (t, AssetType.label(t))],
                value: _filterType,
                onChanged: (v) {
                  setState(() => _filterType = v ?? '');
                  _render();
                },
              ),
              size: 11,
            ),
            ImdLabeled(
              'تصفية بالحالة',
              ImdSelect<String>(
                items: [
                  ('', 'كل الحالات'),
                  for (final s in AssetStatus.all) (s, AssetStatus.label(s)),
                ],
                value: _filterStatus,
                onChanged: (v) {
                  setState(() => _filterStatus = v ?? '');
                  _render();
                },
              ),
              size: 11,
            ),
          ]),
        ]),
      ),
      ImdGrid2(children: [
        ImdPanel(
          margin: EdgeInsets.zero,
          title: cur != null ? 'تعديل: ${cur.name}' : 'إضافة أصل جديد',
          icon: cur != null ? 'edit' : 'plus-square',
          child: _form(can),
        ),
        ImdPanel(
          margin: EdgeInsets.zero,
          title: 'سجل الأصول',
          icon: 'list',
          child: _table(rows, can),
        ),
      ]),
    ]);
  }

  Widget _form(bool can) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImdF2(children: [
            ImdLabeled('اسم الأصل *', ImdFld(controller: _name, enabled: can), size: 11),
            ImdLabeled(
              'النوع *',
              ImdSelect<String>(
                items: [for (final t in AssetType.all) (t, AssetType.label(t))],
                value: _type,
                onChanged: can ? (v) => setState(() => _type = v ?? AssetType.equipment) : null,
              ),
              size: 11,
            ),
            ImdLabeled('الرقم التسلسلي', ImdFld(controller: _serial, enabled: can), size: 11),
            ImdLabeled(
              'الحالة *',
              ImdSelect<String>(
                items: [for (final s in AssetStatus.all) (s, AssetStatus.label(s))],
                value: _status,
                onChanged: can ? (v) => setState(() => _status = v ?? AssetStatus.isNew) : null,
              ),
              size: 11,
            ),
            ImdLabeled(
              'تاريخ الاقتناء',
              ImdDateField(
                value: _acquired,
                enabled: can,
                onChanged: (v) => setState(() => _acquired = v),
              ),
              size: 11,
            ),
            ImdLabeled(
              'العمر الافتراضي (شهر)',
              ImdFld(controller: _lifespan, number: true, enabled: can),
              size: 11,
            ),
            ImdLabeled('القيمة', ImdFld(controller: _value, number: true, enabled: can), size: 11),
            ImdLabeled('رقم الفاتورة', ImdFld(controller: _invoice, enabled: can), size: 11),
            ImdLabeled(
              'المستودع',
              ImdSelect<String>(
                items: [
                  ('', '— بلا مستودع —'),
                  for (final w in _warehouses)
                    if (Perm.of(context).canWh(w.name)) (w.name, w.name),
                ],
                value: _warehouse,
                onChanged: can ? (v) => setState(() => _warehouse = v ?? '') : null,
              ),
              size: 11,
            ),
            ImdLabeled(
              'المرفق',
              ImdSelect<String>(
                items: [('', '— بلا مرفق —'), for (final f in _facilities) (f.id, f.name)],
                value: _facilityId,
                onChanged: can ? (v) => setState(() => _facilityId = v ?? '') : null,
              ),
              size: 11,
            ),
            ImdLabeled(
              'الوحدة المستفيدة',
              ImdSelect<String>(
                items: [('', '— بلا وحدة —'), for (final u in _units) (u.id, u.name)],
                value: _unitId,
                onChanged: can ? (v) => setState(() => _unitId = v ?? '') : null,
              ),
              size: 11,
            ),
            ImdLabeled(
              'المورّد',
              ImdSelect<String>(
                items: [('', '— بلا مورّد —'), for (final s in _suppliers) (s.id, s.name)],
                value: _supplierId,
                onChanged: can ? (v) => setState(() => _supplierId = v ?? '') : null,
              ),
              size: 11,
            ),
          ]),
          const SizedBox(height: 10),
          ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 3, enabled: can)),
          const SizedBox(height: 12),
          const ImdNote(
            'الأصل يقف في **مرفق أو وحدة أو مستودع** — حدّد واحدًا على الأقل، وإلا لم '
            'يُعرف من يُسأل عنه عند الجرد.',
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            ImdButton(
              label: _editId == null ? 'إضافة' : 'حفظ التعديل',
              icon: 'check',
              onPressed: can ? _save : null,
            ),
            if (_editId != null)
              ImdButton.outline(label: 'إلغاء', icon: 'x', onPressed: () => _loadForm(null)),
          ]),
        ],
      );

  Widget _table(List<Asset> rows, bool can) => ImdTable(
        empty: 'لا توجد أصول مسجّلة',
        minWidth: 720,
        columns: const [
          ImdCol('الأصل'),
          ImdCol('النوع'),
          ImdCol('الموضع'),
          ImdCol('الحالة'),
          ImdCol('العمر'),
          ImdCol('إجراءات', center: true),
        ],
        rows: [
          for (final a in rows)
            [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (a.serialNumber.isNotEmpty)
                  Text(a.serialNumber,
                      style: TextStyle(fontSize: 11.5, color: context.imd.muted)),
              ]),
              Text(AssetType.label(a.assetType)),
              Text(_placeOf(a)),
              ImdChip(AssetStatus.label(a.status), tone: _statusTone(a.status)),
              _lifeCell(a),
              Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                ImdIconButton(
                  icon: 'qr-code',
                  tooltip: 'الباركود',
                  onPressed: () => showAssetBarcodeSheet(context, a),
                ),
                ImdIconButton(
                  icon: _openAssignments.containsKey(a.id) ? 'rotate-ccw' : 'users',
                  tooltip: _openAssignments.containsKey(a.id) ? 'استرجاع العهدة' : 'تسليم عهدة',
                  onPressed: can ? () => _assign(a) : null,
                ),
                ImdIconButton(
                  icon: 'edit',
                  tooltip: 'تعديل',
                  onPressed: can ? () => _loadForm(a) : null,
                ),
                ImdIconButton(
                  icon: 'trash',
                  tooltip: 'حذف',
                  onPressed: can ? () => _delete(a) : null,
                ),
              ]),
            ],
        ],
      );

  String _placeOf(Asset a) {
    final open = _openAssignments[a.id];
    if (open != null) return 'عهدة: ${open.beneficiaryUnitName}';
    for (final v in [a.beneficiaryUnitName, a.facilityName, a.warehouse]) {
      if (v.trim().isNotEmpty) return v;
    }
    return '—';
  }

  static ImdTone _statusTone(String status) => switch (status) {
        AssetStatus.isNew => ImdTone.ok,
        AssetStatus.used => ImdTone.info,
        AssetStatus.maintenance => ImdTone.pend,
        AssetStatus.damaged || AssetStatus.consumed => ImdTone.err,
        _ => ImdTone.off,
      };

  Widget _lifeCell(Asset a) {
    final left = AssetRules.daysLeft(
      acquisitionDate: a.acquisitionDate,
      lifespanMonths: a.lifespanMonths,
    );
    if (left == null) return Text('—', style: TextStyle(color: context.imd.faint));
    if (left < 0) return ImdChip('انقضى منذ ${nf(-left)} يوم', tone: ImdTone.err);
    if (left <= AssetRules.warnWithin.inDays) {
      return ImdChip('يتبقى ${nf(left)} يوم', tone: ImdTone.pend);
    }
    return Text('${nf(left)} يوم', style: TextStyle(color: context.imd.muted));
  }
}
