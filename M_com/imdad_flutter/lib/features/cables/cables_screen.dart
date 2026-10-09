import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/print/cable_print.dart';
import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/access_control.dart';
import '../../data/repos/cable_repo.dart';
import '../../domain/free_table.dart';
import 'cable_form.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/print_forms.dart';

/// شاشة البرقيات الرسمية — واردة وصادرة مع مرفق PDF اختياري.

String _d(String iso) {
  final dt = DateTime.tryParse(iso);
  return dt == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(dt);
}

ImdTone _classTone(String k) => switch (k) {
      CableClass.secret => ImdTone.pend,
      CableClass.top => ImdTone.err,
      _ => ImdTone.off,
    };

ImdTone _prioTone(String k) => switch (k) {
      CablePriority.urgent => ImdTone.pend,
      CablePriority.immediate => ImdTone.err,
      _ => ImdTone.off,
    };

ImdTone _statusTone(String k) => switch (k) {
      CableStatus.neu => ImdTone.info,
      CableStatus.processing => ImdTone.pend,
      CableStatus.replied => ImdTone.ok,
      CableStatus.archived => ImdTone.code,
      _ => ImdTone.off,
    };

class CablesScreen extends StatefulWidget {
  const CablesScreen({super.key});

  @override
  State<CablesScreen> createState() => _CablesScreenState();
}

class _CablesScreenState extends State<CablesScreen> {
  final _q = TextEditingController();
  Timer? _debounce;

  String _direction = '';
  String _status = '';
  String _classification = '';
  String _priority = '';
  bool _onlyWithAttach = false;

  List<Cable>? _items;
  Map<String, int> _stats = const {};

  late final CableRepo _repo;
  late final Perm _perm;

  bool get _canCreate => _perm.has('cables', PermAction.create);
  bool get _canEdit => _perm.has('cables', PermAction.edit);
  bool get _canDelete => _perm.has('cables', PermAction.delete);
  bool get _canPrint => _perm.has('cables', PermAction.print);

  @override
  void initState() {
    super.initState();
    _repo = CableRepo(context.read<AppDatabase>());
    _perm = Perm.of(context);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) _load();
    });
    setState(() {});
  }

  Future<void> _load() async {
    final items = await _repo.list(
      q: _q.text,
      direction: _direction,
      status: _status,
      classification: _classification,
      priority: _priority,
      onlyWithAttach: _onlyWithAttach,
    );
    final stats = await _repo.stats();
    if (!mounted) return;
    setState(() {
      _items = items;
      _stats = stats;
    });
  }

  Future<void> _refresh() async {
    await _load();
    if (mounted) showImdToast(context, '✔ تم التحديث');
  }

  bool get _hasFilter =>
      _q.text.trim().isNotEmpty ||
      _direction.isNotEmpty ||
      _status.isNotEmpty ||
      _classification.isNotEmpty ||
      _priority.isNotEmpty ||
      _onlyWithAttach;

  Future<void> _add() async {
    if (!_canCreate) {
      return showImdToast(context, '✖ لا تملك صلاحية الإضافة', error: true);
    }
    final id = await _showForm();
    if (id != null) {
      await _load();
      if (mounted) showImdToast(context, '✔ أُضيفت البرقية');
      // عرض إرفاق PDF مباشرة بعد الإضافة
      final c = await _repo.byId(id);
      if (c != null && mounted) {
        final want = await imdConfirm(
          context,
          'هل تريد إرفاق ملف PDF بالبرقية الآن؟',
          ok: 'إرفاق PDF',
        );
        if (want == true && mounted) await _attachPdf(c);
      }
    }
  }

  Future<void> _edit(Cable c) async {
    if (!_canEdit) {
      return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    }
    final id = await _showForm(initial: c);
    if (id != null) await _load();
  }

  Future<void> _attachPdf(Cable c) async {
    if (!_canEdit) {
      return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    }
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      if (!mounted) return;
      final path = res.files.first.path;
      if (path == null || path.isEmpty) {
        return showImdToast(context, '✖ تعذّر الوصول لمسار الملف', error: true);
      }
      await _repo.attachPdf(c, sourcePath: path, actor: _perm.email);
      await _load();
      if (mounted) showImdToast(context, '✔ أُرفق ملف PDF');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ فشل الإرفاق: $e', error: true);
    }
  }

  Future<void> _removeAttach(Cable c) async {
    if (!_canEdit) {
      return showImdToast(context, '✖ لا تملك صلاحية التعديل', error: true);
    }
    if (!await imdConfirm(
      context,
      'إزالة المرفق «${c.attachName}» من البرقية؟',
      ok: 'إزالة',
      danger: true,
    )) {
      return;
    }
    await _repo.removeAttachment(c, actor: _perm.email);
    await _load();
    if (mounted) showImdToast(context, '✔ أُزيل المرفق');
  }

  Future<void> _openPdf(Cable c) async {
    if (c.attachPath.isEmpty) return;
    final f = File(c.attachPath);
    final exists = await f.exists();
    if (!mounted) return;
    if (!exists) {
      return showImdToast(context, '✖ الملف غير موجود على القرص', error: true);
    }
    final ok = await _repo.verifyAttachment(c);
    if (!ok && mounted) {
      showImdToast(context, '⚠ تحذير: بصمة الملف لا تطابق المخزّن', error: true);
    }
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    await showImdModal<void>(
      context,
      title: c.attachName.isEmpty ? 'مرفق PDF' : c.attachName,
      icon: 'file',
      maxWidth: 720,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: PdfPreview(
          build: (_) async => bytes,
          allowPrinting: true,
          allowSharing: true,
          canChangePageFormat: false,
          canChangeOrientation: false,
        ),
      ),
      actions: (ctx) => [
        ImdButton.outline(
          label: 'تنزيل نسخة',
          icon: 'download',
          onPressed: () async {
            final path = await FilePicker.platform.saveFile(
              fileName: c.attachName.isEmpty ? 'cable.pdf' : c.attachName,
              bytes: bytes,
            );
            if (path != null && mounted) {
              showImdToast(context, '✔ حُفظت النسخة');
            }
          },
        ),
        ImdButton(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop()),
      ],
    );
  }

  Future<void> _changeStatus(Cable c) async {
    if (!_canEdit) {
      return showImdToast(context, '✖ لا تملك صلاحية تغيير الحالة', error: true);
    }
    final choice = await showImdModal<String>(
      context,
      title: 'تغيير حالة البرقية',
      icon: 'swap',
      maxWidth: 420,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('البرقية: ${c.cableNo.isEmpty ? c.subject : c.cableNo}',
              style: TextStyle(color: ctx.imd.muted)),
          const SizedBox(height: 12),
          for (final e in CableStatus.meta.entries)
            if (e.key != c.status)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ImdButton.outline(
                  label: e.value.$1,
                  small: true,
                  onPressed: () => Navigator.of(ctx).pop(e.key),
                ),
              ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await _repo.setStatus(c, choice, actor: _perm.email);
    await _load();
    if (mounted) {
      showImdToast(context, '✔ الحالة: ${CableStatus.label(choice)}');
    }
  }

  Future<void> _delete(Cable c) async {
    if (!_canDelete) {
      return showImdToast(context, '✖ لا تملك صلاحية الحذف', error: true);
    }
    if (!await imdConfirm(
      context,
      'حذف البرقية «${c.cableNo.isEmpty ? c.subject : c.cableNo}» نهائيًّا؟'
      '${c.attachPath.isNotEmpty ? '\nسيُحذف المرفق معها.' : ''}',
      ok: 'حذف',
      danger: true,
    )) {
      return;
    }
    await _repo.delete(c, actor: _perm.email);
    await _load();
    if (mounted) showImdToast(context, '✔ حُذفت البرقية');
  }

  Future<void> _view(Cable c) async {
    // أعد تحميل السجل لأحدث بيانات المرفق
    final fresh = await _repo.byId(c.id) ?? c;
    if (!mounted) return;
    await showImdModal<void>(
      context,
      title: fresh.subject,
      icon: 'mail',
      maxWidth: 700,
      builder: (ctx) {
        final t = ctx.imd;
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 96, maxWidth: 120),
                      child: Text(k,
                          style: TextStyle(
                              fontSize: 13,
                              color: t.muted,
                              fontWeight: FontWeight.w600))),
                  Expanded(
                      child: Text(v.isEmpty ? '—' : v,
                          style: TextStyle(fontSize: 14, color: t.text))),
                ],
              ),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 8, runSpacing: 6, children: [
              ImdChip(CableDirection.label(fresh.direction),
                  tone: fresh.direction == CableDirection.incoming
                      ? ImdTone.info
                      : ImdTone.code),
              ImdChip(CableClass.label(fresh.classification),
                  tone: _classTone(fresh.classification)),
              ImdChip(CablePriority.label(fresh.priority),
                  tone: _prioTone(fresh.priority)),
              ImdChip(CableStatus.label(fresh.status),
                  tone: _statusTone(fresh.status)),
              if (fresh.attachPath.isNotEmpty)
                const ImdChip('PDF', tone: ImdTone.err, icon: 'file'),
            ]),
            const SizedBox(height: 14),
            row('الرقم', fresh.cableNo),
            row('التاريخ', _d(fresh.cableDate)),
            row('من', fresh.fromParty),
            row('إلى', fresh.toParty),
            if (fresh.ccParty.isNotEmpty) row('نسخة إلى', fresh.ccParty),
            if (fresh.cableTime.isNotEmpty) row('ساعة الإنشاء', fresh.cableTime),
            if (!FreeTable.decode(fresh.recipientsJson).isEmpty)
              row(
                  FreeTable.decode(fresh.recipientsJson).title.isEmpty ? 'الجدول' : FreeTable.decode(fresh.recipientsJson).title,
                  FreeTable.decode(fresh.recipientsJson)
                      .filledRows
                      .map((r) => r.where((e) => e.isNotEmpty).join(' — '))
                      .join(', ')),
            if (fresh.replyToNo.isNotEmpty) row('رد على', fresh.replyToNo),
            const SizedBox(height: 8),
            Text('النص',
                style: TextStyle(
                    fontSize: 13, color: t.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.subtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(fresh.body.isEmpty ? '—' : fresh.body,
                  style: TextStyle(fontSize: 14, height: 1.7, color: t.text)),
            ),
            if (fresh.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              row('ملاحظات', fresh.notes),
            ],
            const SizedBox(height: 14),
            // ─── بطاقة المرفق ───
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: t.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: fresh.attachPath.isEmpty
                  ? Row(children: [
                      ImdIcon('file', size: 20, color: t.muted),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text('لا مرفق PDF',
                              style: TextStyle(color: t.muted, fontSize: 13.5))),
                      if (_canEdit)
                        ImdButton.outline(
                            label: 'إرفاق PDF',
                            icon: 'upload',
                            small: true,
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _attachPdf(fresh);
                            }),
                    ])
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          ImdIcon('file', size: 22, color: t.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(fresh.attachName,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: t.text)),
                                Text(CableRepo.formatSize(fresh.attachSize),
                                    style: TextStyle(
                                        fontSize: 12, color: t.muted)),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          ImdButton(
                              label: 'عرض PDF',
                              icon: 'eye',
                              small: true,
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _openPdf(fresh);
                              }),
                          if (_canEdit) ...[
                            ImdButton.outline(
                                label: 'استبدال',
                                icon: 'upload',
                                small: true,
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _attachPdf(fresh);
                                }),
                            ImdButton.outline(
                                label: 'إزالة',
                                icon: 'trash',
                                small: true,
                                onPressed: () {
                                  Navigator.of(ctx).pop();
                                  _removeAttach(fresh);
                                }),
                          ],
                        ]),
                      ],
                    ),
            ),
          ],
        );
      },
      actions: (ctx) => [
        if (_canPrint)
          ImdButton.outline(label: 'طباعة النموذج', icon: 'printer', onPressed: () => _printForm(fresh)),
        if (_canEdit)
          ImdButton.outline(
              label: 'تعديل',
              icon: 'edit',
              onPressed: () {
                Navigator.of(ctx).pop();
                _edit(fresh);
              }),
        ImdButton(
            label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop()),
      ],
    );
  }

  /// يفتح نموذج البرقية. يعيد معرّفها عند الحفظ أو null عند الإلغاء، ويطبعها
  /// فورًا إن اختار المستخدم «حفظ وطباعة».
  Future<String?> _showForm({Cable? initial}) async {
    final res = await showImdModal<CableFormResult>(
      context,
      title: initial == null ? 'برقية جديدة' : 'تعديل برقية',
      icon: 'mail',
      maxWidth: 900,
      builder: (ctx) => CableForm(repo: _repo, initial: initial, actor: _perm.email, canPrint: _canPrint),
    );
    if (res == null) return null;
    if (res.print) {
      final saved = await _repo.byId(res.id);
      if (saved != null && mounted) await _printForm(saved);
    }
    return res.id;
  }

  /// يطبع نموذج البرقية المعتمد (لا سجل البرقيات).
  Future<void> _printForm(Cable c) async {
    if (!_canPrint) {
      return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    }
    try {
      await CablePrint.print(context.read<AppDatabase>(), c);
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  Future<void> _printList() async {
    if (!_canPrint) {
      return showImdToast(context, '✖ لا تملك صلاحية الطباعة', error: true);
    }
    final list = _items ?? const <Cable>[];
    // كان السجل يُطبع بـ`PrintLayout.defaults` وحده: نموذجُ البرقية نفسه يقرأ
    // التخطيط المحفوظ، وسجلُّها لا — ورقتان من نظامٍ واحد بهيئتين.
    final layout = await SettingsRepo(context.read<AppDatabase>()).printLayoutFor(PrintForms.cableLog);
    if (!mounted) return;
    try {
      await DocumentPdf.printDoc(
        layout: layout,
        doc: PrintDoc(
          title: 'سجل البرقيات',
          landscape: true,
          headers: const [
            'م', 'الاتجاه', 'الرقم', 'التاريخ', 'الموضوع',
            'من', 'إلى', 'التصنيف', 'الأولوية', 'الحالة', 'مرفق',
          ],
          rows: [
            for (var i = 0; i < list.length; i++)
              [
                '${i + 1}',
                CableDirection.label(list[i].direction),
                list[i].cableNo,
                _d(list[i].cableDate),
                list[i].subject,
                list[i].fromParty,
                list[i].toParty,
                CableClass.label(list[i].classification),
                CablePriority.label(list[i].priority),
                CableStatus.label(list[i].status),
                list[i].attachPath.isNotEmpty ? 'نعم' : '—',
              ],
          ],
          footerNote: 'العدد: ${nf(list.length)} · ${arDate(DateTime.now())}',
        ),
      );
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّرت الطباعة: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    if (!perm.has('cables')) {
      return const ImdPage(children: [ImdPanel(child: ImdEmptyState.noPermission())]);
    }

    final c = context.imd;
    final list = _items ?? const <Cable>[];

    return ImdPage(children: [
      const ImdPageTitle(
        title: 'البرقيات',
        icon: 'mail',
        subtitle:
            'سجل البرقيات الواردة والصادرة — تصنيف وأولوية وحالة ومع مرفق PDF',
      ),

      ImdKpis(children: [
        ImdKpi(label: 'الإجمالي', value: nf(_stats['total'] ?? 0), icon: 'mail', color: c.accent),
        ImdKpi(label: 'واردة', value: nf(_stats['in'] ?? 0), icon: 'download', color: c.info),
        ImdKpi(label: 'صادرة', value: nf(_stats['out'] ?? 0), icon: 'upload', color: c.success),
        ImdKpi(label: 'جديد', value: nf(_stats['new'] ?? 0), icon: 'plus', color: c.accent),
        ImdKpi(label: 'قيد المعالجة', value: nf(_stats['processing'] ?? 0), icon: 'clock', color: c.warn),
        ImdKpi(label: 'بمرفق PDF', value: nf(_stats['withAttach'] ?? 0), icon: 'file', color: c.danger),
      ]),

      const SizedBox(height: 12),

      ImdPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ImdGrid(columns: 5, minItemWidth: 150, gap: 12, children: [
              ImdLabeled('بحث', ImdFld(controller: _q, hint: 'رقم، موضوع، جهة…', onChanged: _onSearch)),
              ImdLabeled('الاتجاه', ImdSelect<String>(
                items: [('', 'الكل'), for (final e in CableDirection.labels.entries) (e.key, e.value)],
                value: _direction,
                onChanged: (v) { setState(() => _direction = v ?? ''); _load(); },
              )),
              ImdLabeled('الحالة', ImdSelect<String>(
                items: [('', 'الكل'), for (final e in CableStatus.meta.entries) (e.key, e.value.$1)],
                value: _status,
                onChanged: (v) { setState(() => _status = v ?? ''); _load(); },
              )),
              ImdLabeled('التصنيف', ImdSelect<String>(
                items: [('', 'الكل'), for (final e in CableClass.meta.entries) (e.key, e.value.$1)],
                value: _classification,
                onChanged: (v) { setState(() => _classification = v ?? ''); _load(); },
              )),
              ImdLabeled('الأولوية', ImdSelect<String>(
                items: [('', 'الكل'), for (final e in CablePriority.meta.entries) (e.key, e.value.$1)],
                value: _priority,
                onChanged: (v) { setState(() => _priority = v ?? ''); _load(); },
              )),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (_canCreate)
                ImdButton(label: 'برقية جديدة', icon: 'plus', small: true, onPressed: _add),
              ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _refresh),
              ImdButton.outline(
                label: _onlyWithAttach ? 'كل البرقيات' : 'بمرفق فقط',
                icon: 'file',
                small: true,
                onPressed: () {
                  setState(() => _onlyWithAttach = !_onlyWithAttach);
                  _load();
                },
              ),
              if (_hasFilter)
                ImdButton.outline(
                    label: 'مسح المرشحات',
                    icon: 'eraser',
                    small: true,
                    onPressed: () {
                      _q.clear();
                      setState(() {
                        _direction = _status = _classification = _priority = '';
                        _onlyWithAttach = false;
                      });
                      _load();
                    }),
              if (_canPrint)
                ImdButton.outline(label: 'طباعة السجل', icon: 'printer', small: true, onPressed: _printList),
              ImdChip('النتائج: ${nf(list.length)}', tone: ImdTone.ok, icon: 'check'),
            ]),
          ],
        ),
      ),

      const SizedBox(height: 16),

      if (_items == null)
        const ImdLd('جارٍ تحميل البرقيات…')
      else if (list.isEmpty)
        ImdEmptyState.custom(
          title: 'لا برقيات مسجَّلة',
          icon: 'mail',
          message: 'أضف أول برقية واردة أو صادرة، ويمكن إرفاق PDF بها.',
          action: _canCreate
              ? ImdButton(label: 'برقية جديدة', icon: 'plus', onPressed: _add)
              : null,
        )
      else
        ImdTable(
          pageSize: 50,
          columns: const [
            ImdCol('الاتجاه'),
            ImdCol('الرقم'),
            ImdCol('التاريخ'),
            ImdCol('الموضوع', flex: 3),
            ImdCol('من'),
            ImdCol('إلى'),
            ImdCol('السرية'),
            ImdCol('الأسبقية'),
            ImdCol('الحالة'),
            ImdCol('مرفق'),
            ImdCol(''),
          ],
          rows: [
            for (final item in list)
              [
                ImdChip(CableDirection.label(item.direction),
                    tone: item.direction == CableDirection.incoming ? ImdTone.info : ImdTone.code,
                    icon: item.direction == CableDirection.incoming ? 'arrow-down' : 'arrow-up'),
                Text(item.cableNo.isEmpty ? '—' : item.cableNo, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                Text(_d(item.cableDate)),
                Text(item.subject, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                Text(item.fromParty.isEmpty ? '—' : item.fromParty),
                Text(item.toParty.isEmpty ? '—' : item.toParty),
                ImdChip(CableClass.label(item.classification), tone: _classTone(item.classification)),
                ImdChip(CablePriority.label(item.priority), tone: _prioTone(item.priority)),
                ImdChip(CableStatus.label(item.status), tone: _statusTone(item.status)),
                item.attachPath.isNotEmpty
                    ? ImdIconButton(icon: 'file', tooltip: item.attachName, onPressed: () => _openPdf(item))
                    : Text('—', style: TextStyle(color: c.faint)),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  ImdIconButton(icon: 'eye', tooltip: 'عرض', onPressed: () => _view(item)),
                  if (_canPrint) ImdIconButton(icon: 'printer', tooltip: 'طباعة النموذج', onPressed: () => _printForm(item)),
                  if (_canEdit)
                    ImdIconButton(
                        icon: 'upload',
                        tooltip: item.attachPath.isEmpty ? 'إرفاق PDF' : 'استبدال PDF',
                        onPressed: () => _attachPdf(item)),
                  if (_canEdit) ImdIconButton(icon: 'swap', tooltip: 'تغيير الحالة', onPressed: () => _changeStatus(item)),
                  if (_canEdit) ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => _edit(item)),
                  if (_canDelete)
                    ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _delete(item)),
                ]),
              ],
          ],
          empty: 'لا برقيات مطابقة',
          onRowTap: null,
        ),
    ]);
  }
}
