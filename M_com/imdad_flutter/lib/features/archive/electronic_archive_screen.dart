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
import '../../data/repos/catalog_repo.dart';
import '../../domain/access_control.dart';
import 'archive_auto_settings.dart';
import 'electronic_archive/archive_image.dart';

part 'electronic_archive/archive_card.dart';
part 'electronic_archive/archive_view_body.dart';
part 'electronic_archive/archive_upload_sheet.dart';
part 'electronic_archive/archive_meta_form.dart';


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
    final whs = await CatalogRepo(_db).warehouses();
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
      // صريحةً بعد فكّ التشفير: النسخة المنزَّلة تُفتح خارج النظام.
      final bytes = await _repo.bytesOf(f);
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
