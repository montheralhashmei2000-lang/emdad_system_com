import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_drop_zone.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/archive_auto.dart';
import '../../data/repos/archive_repo.dart';
import '../../domain/access_control.dart';
import 'archive_auto_settings.dart';

/// الأرشيف الإلكتروني — مركز حفظ المستندات والملفات (سندات ممحوحة، عقود
/// مسوّحة ضوئيًّا، كشوفات…) بجانب بياناتها الوصفية: تصنيفٌ ووسومٌ ورقم سندٍ
/// مرتبط ومستودع وتاريخ.
///
/// **مصدران للأرشفة**: يدويٌّ من هذه الشاشة (ملفاتٌ متعددة ببياناتٍ مشتركة)،
/// وتلقائيٌّ عند الطباعة — كل عمليةٍ مخزنية وتقاريرٌ لها مفتاحٌ مستقلٌّ في
/// «الإعدادات ← الأرشفة التلقائية»، ومن تُفعَّل أُرشفت نسختها المطبوعة
/// بشارة «تلقائي» ونوع عمليتها، وتُرشَّح هنا مثل سواها.
///
/// **بنية الشاشة**: مؤشراتٌ أعلى، لوحة مرشّحات، ثم العرض بوجهين — جدولٌ
/// كثيف على سطح المكتب وبطاقاتٌ مصوّرة على الجوال (وبنقرتك). الملفات تُعاين
/// داخل التطبيق (صورٌ وPDF) وتُنزَّل نسخةً للعمل عليها خارجًا.
///
/// الصلاحيات صفحة `archive`: view / create / edit / delete / print.
class ElectronicArchiveScreen extends StatefulWidget {
  const ElectronicArchiveScreen({super.key});

  @override
  State<ElectronicArchiveScreen> createState() => _ElectronicArchiveScreenState();
}

/// وجه العرض: جدول أو بطاقات.
enum _ViewMode { table, cards }

class _ElectronicArchiveScreenState extends State<ElectronicArchiveScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final ArchiveRepo _repo = ArchiveRepo(_db);
  late final Perm _perm = Perm.of(context);

  final _q = TextEditingController();

  _ViewMode _view = _ViewMode.table;
  String _category = '';
  String _warehouse = '';
  String _tag = '';
  String _from = '';
  String _to = '';
  String _source = ''; // '' | manual | auto
  String _op = ''; // '' | مفتاح عملية من kArchiveOps
  bool _pinnedOnly = false;

  List<ArchiveFile>? _rows;
  List<Warehouse> _whs = const [];
  Set<String> _categories = const {};
  Set<String> _tags = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  // ───────── الصلاحيات ─────────
  bool get _canCreate => _perm.has('archive', PermAction.create);
  bool _canEdit(ArchiveFile f) =>
      _perm.has('archive', PermAction.edit) && _perm.canWh(f.warehouse);
  bool _canDelete(ArchiveFile f) =>
      _perm.has('archive', PermAction.delete) && _perm.canWh(f.warehouse);

  // ───────── التحميل ─────────
  Future<void> _load() async {
    final rows = await _repo.list();
    final whs = await _db.select(_db.warehouses).get();
    final cats = await _repo.categories();
    final tags = await _repo.tags();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _whs = whs;
      _categories = cats;
      _tags = tags;
    });
  }

  Future<void> _refresh() async {
    await _load();
    if (mounted) showImdToast(context, '✔ تم التحديث');
  }

  void _clearFilters() => setState(() {
        _q.clear();
        _category = '';
        _warehouse = '';
        _tag = '';
        _from = '';
        _to = '';
        _source = '';
        _op = '';
        _pinnedOnly = false;
      });

  bool get _hasFilter =>
      _q.text.trim().isNotEmpty ||
      _category.isNotEmpty ||
      _warehouse.isNotEmpty ||
      _tag.isNotEmpty ||
      _from.isNotEmpty ||
      _to.isNotEmpty ||
      _source.isNotEmpty ||
      _op.isNotEmpty ||
      _pinnedOnly;

  List<ArchiveFile> _filtered() {
    final q = _q.text.trim().toLowerCase();
    return (_rows ?? const <ArchiveFile>[]).where((f) {
      if (_category.isNotEmpty && f.category != _category) return false;
      if (_warehouse.isNotEmpty && f.warehouse != _warehouse) return false;
      if (_source.isNotEmpty && f.source != _source) return false;
      if (_op.isNotEmpty && f.opType != _op) return false;
      if (_pinnedOnly && !f.pinned) return false;
      if (_from.isNotEmpty && f.docDate.compareTo(_from) < 0) return false;
      if (_to.isNotEmpty && f.docDate.compareTo(_to) > 0) return false;
      if (_tag.isNotEmpty && !decodeTags(f.tags).contains(_tag)) return false;
      if (q.isEmpty) return true;
      final hay = [
        f.title,
        f.fileName,
        f.category,
        f.docRef,
        f.warehouse,
        f.notes,
        decodeTags(f.tags).join(' '),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  // ───────── مساعدات العرض ─────────
  String _day(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? (iso.isEmpty ? '—' : arDigits(iso)) : arDate(d);
  }

  String _stamp(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${arDate(t)} · ${arDigits('$hh:$mm')}';
  }

  String _size(int bytes) {
    if (bytes < 1024) return '${nf(bytes)} بايت';
    if (bytes < 1024 * 1024) return '${nf((bytes / 1024).round())} ك.ب';
    return '${nf((bytes / (1024 * 1024) * 10).round() / 10)} م.ب';
  }

  /// (الأيقونة، النبرة) حسب نوع الملف — كل الألوان مشتقّة من رموز السمة.
  (String, ImdTone) _typeView(ArchiveFile f) {
    if (archiveIsPdf(f.fileName)) return ('file', ImdTone.err);
    if (archiveIsImage(f.fileName)) return ('image', ImdTone.ok);
    final ext = f.fileName.split('.').last.toLowerCase();
    if (ext == 'xlsx' || ext == 'xls' || ext == 'csv') return ('calculator', ImdTone.info);
    if (ext == 'docx' || ext == 'doc') return ('edit', ImdTone.info);
    return ('file', ImdTone.off);
  }

  Widget _chip(ArchiveFile f) {
    final (icon, tone) = _typeView(f);
    return ImdChip(f.category, tone: tone, icon: icon, onTap: () => setState(() => _category = f.category));
  }

  /// شارة المصدر ونوع العملية — «تلقائي» تصنعها الطباعة، ويدويٌّ ما رفعه
  /// المستخدم بنفسه من هذه الشاشة.
  List<Widget> _sourceChips(ArchiveFile f) {
    if (f.source != 'auto') return const [];
    return [
      const ImdChip('تلقائي', tone: ImdTone.info, icon: 'zap'),
      if (f.opType.isNotEmpty) ImdChip(archiveOpLabel(f.opType), tone: ImdTone.code),
    ];
  }

  // ───────── إعدادات الأرشفة التلقائية ─────────
  Future<void> _openSettings() async {
    await showImdModal<void>(
      context,
      title: 'إعدادات الأرشفة التلقائية',
      icon: 'zap',
      maxWidth: 620,
      builder: (ctx) => const ArchiveAutoSettingsCard(),
      actions: (ctx) => [ImdButton(label: 'تم', onPressed: () => Navigator.of(ctx).pop())],
    );
    // قد تكون عملياتٌ جديدة أُرشفت بعد تفعيل الإعدادات — حدّث القائمة إن
    // عاد المستخدم.
    if (mounted) await _load();
  }

  // ───────── الأرشفة اليدوية ─────────
  Future<void> _upload() async {
    if (!_canCreate) {
      showImdToast(context, '✖ لا تملك صلاحية أرشفة الملفات', error: true);
      return;
    }
    final saved = await showImdModal<bool>(
      context,
      title: 'أرشفة ملفات',
      icon: 'upload',
      maxWidth: 720,
      builder: (ctx) => _UploadSheet(
        repo: _repo,
        perm: _perm,
        categories: _categories,
        warehouses: _whs.where((w) => _perm.canWh(w.name)).toList(),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظت الملفات في الأرشيف');
    }
  }

  // ───────── العرض ─────────
  Future<void> _openFile(ArchiveFile f) async {
    await showImdModal<void>(
      context,
      title: f.title,
      icon: _typeView(f).$1,
      maxWidth: 900,
      builder: (ctx) => _ViewBody(f: f, repo: _repo, sizeOf: _size, dayOf: _day, stampOf: _stamp),
      actions: (ctx) => [
        ImdButton.outline(label: 'تنزيل نسخة', icon: 'download', onPressed: () => _saveCopy(f)),
        ImdButton.outline(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop()),
      ],
    );
  }

  /// حفظ نسخةٍ من الملف خارج الأرشيف — عبر منتقي حفظ النظام.
  Future<void> _saveCopy(ArchiveFile f) async {
    try {
      final bytes = await File(f.storedPath).readAsBytes();
      final path = await FilePicker.platform.saveFile(fileName: f.fileName, bytes: bytes);
      if (path == null) return;
      // على بعض المنصات يعيد المسار بلا كتابةٍ — نضمن الملف مكتوبًا.
      final out = File(path);
      if (!await out.exists() || await out.length() == 0) {
        await out.writeAsBytes(bytes, flush: true);
      }
      if (mounted) showImdToast(context, '✔ حُفظت النسخة: ${p.basename(path)}');
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّر الحفظ: $e', error: true);
    }
  }

  // ───────── التثبيت ─────────
  Future<void> _togglePin(ArchiveFile f) async {
    await _repo.setPinned(f.id, !f.pinned);
    await _load();
  }

  // ───────── التعديل ─────────
  Future<void> _edit(ArchiveFile f) async {
    if (!_canEdit(f)) {
      showImdToast(context, '✖ لا تملك صلاحية تعديل بيانات الأرشيف', error: true);
      return;
    }
    final saved = await showImdModal<bool>(
      context,
      title: 'تعديل بيانات: ${f.title}',
      icon: 'edit',
      maxWidth: 640,
      builder: (ctx) => _MetaForm(
        repo: _repo,
        perm: _perm,
        categories: _categories,
        warehouses: _whs.where((w) => _perm.canWh(w.name) || w.name == f.warehouse).toList(),
        initial: f,
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) showImdToast(context, '✔ حُفظت تعديلات البيانات');
    }
  }

  // ───────── الحذف ─────────
  Future<void> _delete(ArchiveFile f) async {
    if (!_canDelete(f)) {
      showImdToast(context, '✖ لا تملك صلاحية حذف ملفات الأرشيف', error: true);
      return;
    }
    if (!await imdConfirm(
      context,
      'حذف «${f.title}» من الأرشيف نهائيًّا؟\nسيُحذف الملف المخزَّن مع بياناته، ويُسجَّل ذلك في سجل التدقيق.',
      ok: 'حذف نهائي',
      danger: true,
    )) {
      return;
    }
    await _repo.delete(f, actor: _perm.email);
    await _load();
    if (mounted) showImdToast(context, '✔ حُذف «${f.title}» من الأرشيف');
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    if (!_perm.has('archive', PermAction.view)) {
      return const ImdPage(children: [
        ImdPanel(child: ImdEmptyState.noPermission()),
      ]);
    }
    final c = context.imd;
    final all = _rows ?? const <ArchiveFile>[];
    final rows = _filtered();
    final totalBytes = all.fold<int>(0, (s, f) => s + f.sizeBytes);
    final autoCount = all.where((f) => f.source == 'auto').length;

    final body = <Widget>[
      ImdPageTitle(
        title: 'الأرشيف الإلكتروني',
        icon: 'folder',
        subtitle: 'حفظ المستندات والملفات ببياناتها الوصفية — أرشفةٌ يدوية وتلقائية عند الطباعة، معاينةٌ ووسومٌ وبصمة نزاهة، وكل شيءٍ محليٌّ على جهازك',
        actions: [
          ImdIconButton(icon: 'zap', tooltip: 'إعدادات الأرشفة التلقائية', onPressed: _openSettings),
          ImdSegmented<_ViewMode>(
            tabs: const [
              ImdTab(_ViewMode.table, 'جدول', icon: 'database'),
              ImdTab(_ViewMode.cards, 'بطاقات', icon: 'square'),
            ],
            value: _view,
            onChanged: (v) => setState(() => _view = v),
          ),
          if (_canCreate)
            ImdButton(label: 'أرشفة ملفات', icon: 'upload', onPressed: _upload),
        ],
      ),

      // المؤشرات: حجمُ الأرشيف ومحتواه في نظرة.
      ImdKpis(children: [
        ImdKpi(label: 'ملفات مؤرشفة', value: nf(all.length), icon: 'folder', color: c.accent),
        ImdKpi(label: 'الحجم الكلي', value: _size(totalBytes), icon: 'database', color: c.info),
        ImdKpi(label: 'من الطباعة تلقائيًّا', value: nf(autoCount), icon: 'zap', color: c.warn),
        ImdKpi(label: 'مثبَّت للوصول السريع', value: nf(all.where((f) => f.pinned).length), icon: 'pin', color: c.success),
      ]),

      // المرشّحات — أربعة معنوية ونصّان زمنيان، والمصدر ونوع العملية
      // يفصلان الأرشفة التلقائية عن اليدوية بنقرة.
      ImdPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ImdGrid(columns: 6, minItemWidth: 170, gap: 12, children: [
            ImdLabeled('بحث', ImdFld(controller: _q, hint: 'العنوان، الوسم، رقم السند…', onChanged: (_) => setState(() {}))),
            ImdLabeled(
              'التصنيف',
              ImdSelect<String>(
                items: [('', 'الكل'), for (final cat in _categories.toList()..sort()) (cat, cat)],
                value: _category,
                onChanged: (v) => setState(() => _category = v ?? ''),
              ),
            ),
            ImdLabeled(
              'الوسم',
              ImdSelect<String>(
                items: [('', 'الكل'), for (final t in _tags.toList()..sort()) (t, t)],
                value: _tag,
                onChanged: (v) => setState(() => _tag = v ?? ''),
              ),
            ),
            ImdLabeled(
              'المستودع',
              ImdSelect<String>(
                items: [('', 'الكل'), for (final w in _whs.where((w) => _perm.canWh(w.name))) (w.name, w.name)],
                value: _warehouse,
                onChanged: (v) => setState(() => _warehouse = v ?? ''),
              ),
            ),
            ImdLabeled('من تاريخ المستند', ImdDateField(value: _from, onChanged: (v) => setState(() => _from = v))),
            ImdLabeled('إلى تاريخ المستند', ImdDateField(value: _to, onChanged: (v) => setState(() => _to = v))),
            ImdLabeled(
              'المصدر',
              ImdSelect<String>(
                items: const [
                  ('', 'الكل'),
                  ('auto', 'تلقائي عند الطباعة'),
                  ('manual', 'رفع يدوي'),
                ],
                value: _source,
                onChanged: (v) => setState(() => _source = v ?? ''),
              ),
            ),
            ImdLabeled(
              'نوع العملية',
              ImdSelect<String>(
                items: [('', 'الكل'), for (final op in kArchiveOps) (op.$1, op.$2)],
                value: _op,
                onChanged: (v) => setState(() => _op = v ?? ''),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            ImdButton.outline(label: 'تحديث', icon: 'refresh', small: true, onPressed: _refresh),
            const SizedBox(width: 8),
            if (_hasFilter)
              ImdButton.outline(label: 'مسح المرشحات', icon: 'eraser', small: true, onPressed: _clearFilters),
            const SizedBox(width: 12),
            ImdCheckbox(value: _pinnedOnly, label: 'المثبَّتة فقط', onChanged: (v) => setState(() => _pinnedOnly = v)),
            const Spacer(),
            ImdChip('النتائج: ${nf(rows.length)}', tone: ImdTone.ok, icon: 'check'),
          ]),
        ]),
      ),
      const SizedBox(height: 16),

      // المحتوى: تحميل / فراغ / نتائج.
      if (_rows == null)
        const ImdLd('جارٍ تحميل الأرشيف…')
      else if (all.isEmpty)
        ImdEmptyState.custom(
          title: 'الأرشيف فارغ',
          icon: 'folder',
          message: 'أرشف أول ملفٍ لتكوين مكتبة مستندات جهازك، أو فعّل الأرشفة التلقائية (زرّ الصاعقة) فتُؤرشف السندات والتقارير المطبوعة من تلقاء نفسها.',
          action: _canCreate
              ? ImdButton(label: 'أرشف ملفك الأول', icon: 'upload', onPressed: _upload)
              : null,
        )
      else if (rows.isEmpty)
        ImdEmptyState.noResults(
          message: 'لا ملفاتٍ تطابق المرشّحات الحالية — جرّب مسح المرشحات أو تغيير كلمات البحث.',
          action: ImdButton.outline(label: 'مسح المرشحات', icon: 'eraser', small: true, onPressed: _clearFilters),
        )
      else if (_view == _ViewMode.cards)
        ImdAutoGrid(
          minItem: 250,
          gap: 14,
          bottom: 20,
          children: [for (final f in rows) _ArchiveCard(f: f, state: this)],
        )
      else
        ImdTable(
          columns: const [
            ImdCol('العنوان', flex: 3),
            ImdCol('التصنيف'),
            ImdCol('الوسوم', flex: 2),
            ImdCol('السند المرتبط'),
            ImdCol('المستودع'),
            ImdCol('تاريخ المستند'),
            ImdCol('الحجم', numeric: true),
            ImdCol('المُنشئ'),
            ImdCol(''),
          ],
          rows: [for (final f in rows) _row(f)],
          pageSize: 50,
          empty: 'لا ملفات مطابقة',
          maxHeight: ImdSizes.tableMaxHeight(context),
          onRowTap: (i) => _openFile(rows[i]),
        ),
    ];

    return ImdPage(children: body);
  }

  List<Widget> _row(ArchiveFile f) {
    final (icon, tone) = _typeView(f);
    final (_, fg) = ImdChip.colors(context.imd, tone);
    final tags = decodeTags(f.tags);
    return [
      // العنوان بأيقونة نوعه وشارة مصدره — أسرع من قراءة امتدادٍ في عمودٍ مستقل.
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ImdIcon(icon, size: 15, color: fg),
        Flexible(child: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w700, color: context.imd.text))),
        ..._sourceChips(f),
        if (f.pinned) ImdIcon('pin', size: 13, color: context.imd.accent),
      ]),
      _chip(f),
      Wrap(spacing: 4, runSpacing: 4, children: [
        for (final t in tags.take(2)) ImdChip(t, tone: ImdTone.code),
        if (tags.length > 2) ImdChip('+${nf(tags.length - 2)}', tone: ImdTone.code),
        if (tags.isEmpty) Text('—', style: TextStyle(color: context.imd.faint)),
      ]),
      Text(f.docRef.isEmpty ? '—' : f.docRef, style: TextStyle(fontWeight: f.docRef.isEmpty ? FontWeight.w400 : FontWeight.w600)),
      Text(f.warehouse.isEmpty ? '—' : f.warehouse),
      Text(_day(f.docDate)),
      Text(_size(f.sizeBytes)),
      Text(f.createdBy.isEmpty ? '—' : f.createdBy),
      Wrap(spacing: 6, runSpacing: 6, children: [
        ImdIconButton(icon: 'eye', tooltip: 'عرض', onPressed: () => _openFile(f)),
        ImdIconButton(icon: 'download', tooltip: 'تنزيل نسخة', onPressed: () => _saveCopy(f)),
        ImdIconButton(icon: f.pinned ? 'star' : 'pin', tooltip: f.pinned ? 'إلغاء التثبيت' : 'تثبيت', onPressed: () => _togglePin(f)),
        if (_canEdit(f)) ImdIconButton(icon: 'edit', tooltip: 'تعديل البيانات', onPressed: () => _edit(f)),
        if (_canDelete(f))
          ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => _delete(f)),
      ]),
    ];
  }
}

// ═════════════════════════════ بطاقة الملف ═════════════════════════════

/// بطاقة الملف في عرض البطاقات — صورةٌ مصغّرة للصور، وشارة نوعٍ لغيرها.
class _ArchiveCard extends StatefulWidget {
  const _ArchiveCard({required this.f, required this.state});

  final ArchiveFile f;
  final _ElectronicArchiveScreenState state;

  @override
  State<_ArchiveCard> createState() => _ArchiveCardState();
}

class _ArchiveCardState extends State<_ArchiveCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final f = widget.f;
    final (icon, tone) = widget.state._typeView(f);
    final (_, fg) = ImdChip.colors(c, tone);
    final tags = decodeTags(f.tags);
    final isImage = archiveIsImage(f.fileName);

    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.state._openFile(f),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hover ? c.rowHover : c.surface,
            border: Border.all(color: _hover ? c.accent : c.line),
            borderRadius: BorderRadius.circular(ImdSizes.radius),
            boxShadow: imdShadow(c),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // المعاينة أو شارة النوع.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 110,
                  width: double.infinity,
                  color: c.bg,
                  child: isImage
                      ? Image.file(
                          File(f.storedPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _typeBadge(fg, icon),
                        )
                      : _typeBadge(fg, icon),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Flexible(
                  child: Text(f.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                ),
                if (f.pinned) ...[
                  const SizedBox(width: 6),
                  ImdIcon('pin', size: 13, color: c.accent),
                ],
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                widget.state._chip(f),
                ...widget.state._sourceChips(f),
                Text(widget.state._size(f.sizeBytes), style: TextStyle(fontSize: 12, color: c.muted)),
                Text(widget.state._day(f.docDate), style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
              if (f.docRef.isNotEmpty || f.warehouse.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (f.docRef.isNotEmpty) 'السند: ${f.docRef}',
                    if (f.warehouse.isNotEmpty) f.warehouse,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [for (final t in tags.take(3)) ImdChip(t, tone: ImdTone.code)]),
              ],
              const SizedBox(height: 10),
              // الإجراءات — في سطرٍ واحد تحت المحتوى.
              Row(children: [
                ImdIconButton(icon: 'eye', tooltip: 'عرض', onPressed: () => widget.state._openFile(f)),
                const SizedBox(width: 6),
                ImdIconButton(icon: 'download', tooltip: 'تنزيل نسخة', onPressed: () => widget.state._saveCopy(f)),
                const SizedBox(width: 6),
                ImdIconButton(
                    icon: f.pinned ? 'star' : 'pin',
                    tooltip: f.pinned ? 'إلغاء التثبيت' : 'تثبيت',
                    onPressed: () => widget.state._togglePin(f)),
                const Spacer(),
                if (widget.state._canEdit(f)) ...[
                  ImdIconButton(icon: 'edit', tooltip: 'تعديل', onPressed: () => widget.state._edit(f)),
                  const SizedBox(width: 6),
                ],
                if (widget.state._canDelete(f))
                  ImdIconButton(icon: 'trash', tooltip: 'حذف', kind: ImdBtnKind.danger, onPressed: () => widget.state._delete(f)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(Color fg, String icon) => Center(
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: .12),
            shape: BoxShape.circle,
          ),
          child: ImdIcon(icon, size: 26, color: fg),
        ),
      );
}

// ═════════════════════════════ نافذة العرض ═════════════════════════════

/// جسد نافذة العرض: بياناتٌ وصفية، فحصُ نزاهةٍ بالبصمة، ثم معاينة الملف.
class _ViewBody extends StatelessWidget {
  const _ViewBody({
    required this.f,
    required this.repo,
    required this.sizeOf,
    required this.dayOf,
    required this.stampOf,
  });

  final ArchiveFile f;
  final ArchiveRepo repo;
  final String Function(int) sizeOf;
  final String Function(String) dayOf;
  final String Function(DateTime) stampOf;

  Widget _info(String label, String value, ImdColors c) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: c.muted)),
              Text(value.isEmpty ? '—' : value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
            ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final isImage = archiveIsImage(f.fileName);
    final isPdf = archiveIsPdf(f.fileName);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdGrid(columns: 5, minItemWidth: 150, gap: 8, children: [
        _info('التصنيف', f.category, c),
        _info('تاريخ المستند', dayOf(f.docDate), c),
        _info('السند المرتبط', f.docRef, c),
        _info('المستودع', f.warehouse, c),
        _info('المصدر', f.source == 'auto' ? 'تلقائي عند الطباعة' : 'رفع يدوي', c),
        if (f.source == 'auto' && f.opType.isNotEmpty)
          _info('نوع العملية', archiveOpLabel(f.opType), c)
        else
          _info('الملف الأصلي', f.fileName, c),
        _info('الحجم', sizeOf(f.sizeBytes), c),
        _info('المُنشئ', f.createdBy, c),
        _info('أُرشف في', stampOf(f.createdAt), c),
        _info('آخر تحديث', f.updatedAt == null ? '—' : stampOf(f.updatedAt!), c),
      ]),
      if (f.notes.isNotEmpty) ...[
        const SizedBox(height: 10),
        ImdNote(f.notes),
      ],
      const SizedBox(height: 10),
      // فحص النزاهة: البصمة المخزَّنة مقابل الملف الحالي — إن اختلفتا
      // فقد عُبث بالنسخة بعد الأرشفة.
      FutureBuilder<bool>(
        future: repo.verifyIntegrity(f),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ImdChip('جارٍ فحص نزاهة الملف…', tone: ImdTone.off, icon: 'shield');
          }
          final ok = snap.data == true;
          return ImdChip(
            ok ? 'الملف سليم — البصمة مطابقة لأصلها' : 'تنبيه: تعذّر التحقق من نزاهة الملف!',
            tone: ok ? ImdTone.ok : ImdTone.pend,
            icon: ok ? 'shield' : 'alert',
          );
        },
      ),
      const SizedBox(height: 12),
      if (isImage)
        Container(
          height: 430,
          decoration: BoxDecoration(
            color: c.bg,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(f.storedPath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const ImdNote('تعذّر عرض الصورة — نزّل نسخةً وافتحها خارجيًّا.'),
              ),
            ),
          ),
        )
      else if (isPdf)
        Container(
          height: 480,
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: PdfPreview(
            build: (_) async => File(f.storedPath).readAsBytes(),
            canChangeOrientation: false,
            canChangePageFormat: false,
          ),
        )
      else
        // أنواعٌ لا يعاينها التطبيق: بطاقة إرشادٍ بدل فراغٍ محيّر.
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: c.bg,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ImdIcon('file', size: 48, color: c.faint, strokeWidth: 1.5),
              const SizedBox(height: 10),
              Text('لا توجد معاينة لهذا النوع (${f.fileName.split('.').last.toUpperCase()})',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
              const SizedBox(height: 4),
              Text('نزّل نسخةً من زرّ «تنزيل نسخة» لعرضه بالبرنامج المناسب.',
                  style: TextStyle(fontSize: 12.5, color: c.faint)),
            ]),
          ),
        ),
      if (decodeTags(f.tags).isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final t in decodeTags(f.tags)) ImdChip(t, tone: ImdTone.code, icon: 'tag')]),
      ],
    ]);
  }
}

// ═════════════════════ نماذج الأرشفة والتعديل ═════════════════════

/// نموذج الأرشفة: ملفاتٌ متعددة ببياناتٍ وصفية مشتركة — العنوان يُولَّد من
/// اسم الملف فيُفلت عشرة ملفاتٍ بلا كتابةٍ عشرة عناوين.
class _UploadSheet extends StatefulWidget {
  const _UploadSheet({
    required this.repo,
    required this.perm,
    required this.categories,
    required this.warehouses,
  });

  final ArchiveRepo repo;
  final Perm perm;
  final Set<String> categories;
  final List<Warehouse> warehouses;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  final _category = TextEditingController(text: 'عام');
  final _docRef = TextEditingController();
  final _tags = TextEditingController();
  final _notes = TextEditingController();

  String _warehouse = '';
  String _docDate = isoDay(DateTime.now());
  final _files = <String>[];
  bool _busy = false;

  @override
  void dispose() {
    _category.dispose();
    _docRef.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      if (res == null || res.paths.isEmpty) return;
      setState(() {
        for (final pth in res.paths) {
          if (pth != null && !_files.contains(pth)) _files.add(pth);
        }
      });
    } catch (e) {
      if (mounted) showImdToast(context, '✖ تعذّر اختيار الملفات: $e', error: true);
    }
  }

  /// استقبال ملفٍ مُفلَتٍ من مستكشف ويندوز.
  void _onDrop(String path) {
    setState(() {
      if (!_files.contains(path)) _files.add(path);
    });
  }

  Future<void> _save() async {
    if (_files.isEmpty) {
      showImdToast(context, '✖ اختر ملفًا واحدًا على الأقل', error: true);
      return;
    }
    setState(() => _busy = true);
    var done = 0;
    try {
      for (final path in _files) {
        await widget.repo.archive(
          sourcePath: path,
          title: p.basenameWithoutExtension(path),
          category: _category.text,
          tags: _tags.text.split(RegExp(r'[,،]')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
          docRef: _docRef.text,
          warehouse: _warehouse,
          docDate: _docDate,
          notes: _notes.text,
          createdBy: widget.perm.email,
        );
        done++;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showImdToast(context, '✖ أُرشف ${nf(done)} قبل التعثر — $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return ImdDropZone(
      extensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'xlsx', 'xls', 'csv', 'docx', 'doc', 'txt', 'zip'],
      onFile: _onDrop,
      hint: 'أفلت الملفات هنا لأرشفتها',
      enabled: !_busy,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // قائمة الملفات المنتقاة.
        if (_files.isEmpty)
          Container(
            height: 90,
            decoration: BoxDecoration(
              color: c.subtle,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text('ما من ملفاتٍ بعد — اخترها أو أفلتها فوق النافذة (على ويندوز)',
                  style: TextStyle(fontSize: 12.5, color: c.muted)),
            ),
          )
        else
          ...[
            for (final path in _files)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: c.bg,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  ImdIcon(archiveIsImage(path) ? 'image' : 'file', size: 15, color: c.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.basename(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.text)),
                  ),
                  Text('سيُعنون: ${p.basenameWithoutExtension(path)}',
                      style: TextStyle(fontSize: 11.5, color: c.faint)),
                  const SizedBox(width: 6),
                  ImdIconButton(
                    icon: 'x',
                    tooltip: 'إزالة من القائمة',
                    onPressed: () => setState(() => _files.remove(path)),
                  ),
                ]),
              ),
          ],
        const SizedBox(height: 8),
        ImdButton.outline(label: 'اختيار ملفات', icon: 'plus', small: true, onPressed: _busy ? null : _pick),
        const SizedBox(height: 12),
        ImdGrid(columns: 3, minItemWidth: 180, gap: 10, children: [
          ImdLabeled('التصنيف', ImdFld(controller: _category, suggestions: widget.categories.toList()..sort())),
          ImdLabeled(
            'المستودع (اختياري)',
            ImdSelect<String>(
              items: [('', 'بلا ربط'), for (final w in widget.warehouses) (w.name, w.name)],
              value: _warehouse,
              onChanged: (v) => setState(() => _warehouse = v ?? ''),
            ),
          ),
          ImdLabeled('تاريخ المستند', ImdDateField(value: _docDate, onChanged: (v) => setState(() => _docDate = v))),
          ImdLabeled('السند المرتبط (اختياري)', ImdFld(controller: _docRef, hint: 'رقم سندٍ في سجل المستندات')),
          ImdLabeled('الوسوم (افصل بفاصلة)', ImdFld(controller: _tags, hint: 'سنوي، تعاقد…')),
          ImdLabeled('ملاحظات', ImdFld(controller: _notes)),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
          ImdButton(
            label: _files.isEmpty ? 'أرشف' : 'أرشف ${nf(_files.length)} ملف',
            icon: 'save',
            busy: _busy,
            onPressed: _save,
          ),
        ]),
      ]),
    );
  }
}

/// نموذج تعديل بيانات ملفٍ مؤرشف — بياناته الوصفية وحدها، فالملف نفسه
/// لا يُستبدل من هنا.
class _MetaForm extends StatefulWidget {
  const _MetaForm({
    required this.repo,
    required this.perm,
    required this.categories,
    required this.warehouses,
    required this.initial,
  });

  final ArchiveRepo repo;
  final Perm perm;
  final Set<String> categories;
  final List<Warehouse> warehouses;
  final ArchiveFile initial;

  @override
  State<_MetaForm> createState() => _MetaFormState();
}

class _MetaFormState extends State<_MetaForm> {
  late final TextEditingController _title = TextEditingController(text: widget.initial.title);
  late final TextEditingController _category = TextEditingController(text: widget.initial.category);
  late final TextEditingController _docRef = TextEditingController(text: widget.initial.docRef);
  late final TextEditingController _tags =
      TextEditingController(text: decodeTags(widget.initial.tags).join('، '));
  late final TextEditingController _notes = TextEditingController(text: widget.initial.notes);
  late String _warehouse = widget.initial.warehouse;
  late String _docDate = widget.initial.docDate;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _docRef.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showImdToast(context, '✖ عنوان المستند مطلوب', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.updateMeta(
        widget.initial.id,
        title: _title.text,
        category: _category.text,
        tags: _tags.text.split(RegExp(r'[,،]')).map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
        docRef: _docRef.text,
        warehouse: _warehouse,
        docDate: _docDate,
        notes: _notes.text,
        actor: widget.perm.email,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showImdToast(context, '✖ $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ImdGrid(columns: 2, minItemWidth: 220, gap: 10, children: [
        ImdLabeled('العنوان *', ImdFld(controller: _title)),
        ImdLabeled('التصنيف', ImdFld(controller: _category, suggestions: widget.categories.toList()..sort())),
        ImdLabeled(
          'المستودع',
          ImdSelect<String>(
            items: [('', 'بلا ربط'), for (final w in widget.warehouses) (w.name, w.name)],
            value: _warehouse,
            onChanged: (v) => setState(() => _warehouse = v ?? ''),
          ),
        ),
        ImdLabeled('تاريخ المستند', ImdDateField(value: _docDate, onChanged: (v) => setState(() => _docDate = v))),
        ImdLabeled('السند المرتبط', ImdFld(controller: _docRef)),
        ImdLabeled('الوسوم (افصل بفاصلة)', ImdFld(controller: _tags)),
      ]),
      ImdLabeled('ملاحظات', ImdFld(controller: _notes, maxLines: 3)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
        ImdButton.outline(label: 'إلغاء', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        ImdButton(label: 'حفظ', icon: 'save', busy: _busy, onPressed: _save),
      ]),
    ]);
  }
}
