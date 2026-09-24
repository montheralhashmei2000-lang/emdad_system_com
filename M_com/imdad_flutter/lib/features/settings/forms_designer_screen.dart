import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/print/document_pdf.dart';
import '../../core/security/perm.dart';
import '../../core/ui/imd_fonts.dart';
import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../domain/access_control.dart';
import '../../domain/print_layout.dart';
import '../home/home_shell.dart';
import '../inventory/doc_kit.dart';

/// مصمم النماذج المطبوعة — مقابل `renderFormsDesigner()` في `forms-ux.js`:
/// ترويسة الجهة، حقول أعلى الصفحة، بيانات السند، تنسيق جدول الأصناف،
/// خانات التوقيع والتذييل — مع معاينة فورية بصيغة PDF.
class FormsDesignerScreen extends StatefulWidget {
  const FormsDesignerScreen({super.key});

  @override
  State<FormsDesignerScreen> createState() => _FormsDesignerScreenState();
}

class _FormsDesignerScreenState extends State<FormsDesignerScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final SettingsRepo _settings = SettingsRepo(_db);
  late final Perm _perm = Perm.of(context);

  PrintLayout _layout = PrintLayout.defaults;
  bool _loading = true;
  bool _dirty = false;

  /// نوع المستند المعروض في المعاينة — التخطيط واحد لكن الأعمدة والعناوين
  /// تختلف، فرؤية أثر التعديل على النوع المقصود أصدق من نموذج واحد ثابت.
  String _previewKind = 'receipt';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final layout = await _settings.printLayout();
    if (!mounted) return;
    setState(() {
      _layout = layout;
      _loading = false;
      _dirty = false;
    });
  }

  bool get _editable => _perm.admin || _perm.has('settings', PermAction.edit);

  void _update(PrintLayout next) => setState(() {
        _layout = next;
        _dirty = true;
      });

  /// حارس المغادرة: التخطيط يُحفظ يدويًا، فالخروج بتغييرات غير محفوظة يضيّعها
  /// بلا إنذار — سواء بزر الرجوع أو بزر النظام الخلفي.
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    return imdConfirm(
      context,
      'لديك تغييرات غير محفوظة على تخطيط النماذج. الخروج الآن يفقدها.',
      ok: 'الخروج بلا حفظ',
      danger: true,
    );
  }

  Future<void> _leaveToSettings() async {
    if (!await _confirmLeave()) return;
    if (!mounted) return;
    context.read<ImdNav>().go('settings');
  }

  Future<void> _save() async {
    if (!_perm.guard(context, 'settings', PermAction.edit)) return;
    await _settings.savePrintLayout(_layout);
    if (!mounted) return;
    setState(() => _dirty = false);
    showImdToast(context, '✔ حُفظ تخطيط النماذج المطبوعة');
  }

  /// نماذج المعاينة لكل نوع مستند.
  static const Map<String, ({String label, String title, List<String> headers, List<int> flex, List<List<String>> rows, Map<String, String> fields})> _previews = {
    'receipt': (
      label: 'سند استلام',
      title: 'نموذج معاينة — سند استلام',
      headers: ['م', 'الصنف', 'الوحدة', 'الكمية'],
      flex: [1, 6, 2, 2],
      rows: [
        ['1', 'أرز أبيض', 'كيس', '12'],
        ['2', 'سكر', 'كجم', '250'],
        ['3', 'زيت طعام', 'كرتون', '8'],
      ],
      fields: {'warehouse': 'المخزن الرئيسي', 'party': 'مؤسسة التموين', 'notes': 'معاينة للتنسيق فقط'},
    ),
    'issue': (
      label: 'أمر صرف',
      title: 'نموذج معاينة — أمر صرف',
      headers: ['م', 'الصنف', 'الوحدة', 'الكمية', 'الجهة المستفيدة'],
      flex: [1, 5, 2, 2, 4],
      rows: [
        ['1', 'أرز أبيض', 'كيس', '6', 'سرية الإسناد'],
        ['2', 'عدس', 'كجم', '40', 'سرية الإسناد'],
      ],
      fields: {'warehouse': 'المخزن الرئيسي', 'party': 'اللواء الأول', 'notes': 'صرف إعاشة ٣ أيام'},
    ),
    'transfer': (
      label: 'إذن تحويل',
      title: 'نموذج معاينة — إذن تحويل مخزني',
      headers: ['م', 'الصنف', 'الوحدة', 'الكمية'],
      flex: [1, 6, 2, 2],
      rows: [
        ['1', 'طحين', 'كيس', '20'],
        ['2', 'ملح', 'كجم', '75'],
      ],
      fields: {'warehouse': 'المخزن الرئيسي', 'party': 'مستودع الفرع', 'notes': 'تحويل بين المستودعات'},
    ),
    'return': (
      label: 'سند مرتجع',
      title: 'نموذج معاينة — سند مرتجع',
      headers: ['م', 'الصنف', 'الوحدة', 'الكمية', 'الحالة'],
      flex: [1, 5, 2, 2, 3],
      rows: [
        ['1', 'زيت طعام', 'كرتون', '2', 'صالحة'],
      ],
      fields: {'warehouse': 'المخزن الرئيسي', 'party': 'سرية الإسناد', 'notes': 'مرتجع من وحدة'},
    ),
    'report': (
      label: 'تقرير',
      title: 'نموذج معاينة — تقرير أرصدة',
      headers: ['م', 'الصنف', 'التصنيف', 'الرصيد', 'الوحدة'],
      flex: [1, 5, 3, 2, 2],
      rows: [
        ['1', 'أرز أبيض', 'حبوب', '95', 'كيس'],
        ['2', 'زيت طعام', 'زيوت', '200', 'لتر'],
      ],
      fields: {'warehouse': 'كل المستودعات', 'party': '—', 'notes': 'تقرير تجريبي'},
    ),
  };

  /// معاينة بنموذج من النوع المختار.
  Future<void> _preview() async {
    final p = _previews[_previewKind]!;
    await DocumentPdf.printDoc(
      doc: PrintDoc(
        title: p.title,
        headers: p.headers,
        columnFlex: p.flex,
        rows: p.rows,
        leftValues: const {'date': '1447-01-01', 'entryNo': '12', 'refNo': 'و-000123'},
        fieldValues: p.fields,
      ),
      layout: _layout,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ImdPage(children: [
        ImdPageTitle(title: 'مصمم النماذج المطبوعة', icon: 'printer'),
        ImdLd('⏳ جارٍ التحميل…'),
      ]);
    }
    final w = _editable;

    return PopScope(
      // يُفعَّل فقط حين توجد تغييرات، فلا يعترض الخروج بلا داعٍ.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _leaveToSettings();
      },
      child: ImdStickyPage(
      sticky: ImdStickyActions(children: [
        SizedBox(
          width: 170,
          child: ImdSelect<String>(
            dense: true,
            items: [for (final e in _previews.entries) (e.key, e.value.label)],
            value: _previewKind,
            onChanged: (v) => setState(() => _previewKind = v ?? 'receipt'),
          ),
        ),
        ImdButton.outline(label: 'معاينة النموذج', icon: 'printer', onPressed: _preview),
        if (w) ImdButton(label: 'حفظ التخطيط', icon: 'save', onPressed: _save),
        ImdButton.outline(
          label: 'استعادة الافتراضي',
          icon: 'rotate-ccw',
          onPressed: w ? () => _update(PrintLayout.defaults) : null,
        ),
      ]),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // `injectBackToSettings()` — الشاشتان تُفتحان من الإعدادات فقط.
            child: ImdButton.outline(
              label: 'رجوع إلى الإعدادات',
              icon: 'arrow-left',
              small: true,
              onPressed: _leaveToSettings,
            ),
          ),
        ),
        ImdPageTitle(
          title: 'مصمم النماذج المطبوعة',
          icon: 'printer',
          subtitle: 'الرأس والتذييل وخانات التوقيع وتنسيق جدول الأصناف '
              'لسندات الاستلام والصرف والتحويل والمرتجعات والتقارير',
          trailing: _dirty ? const ImdChip('تغييرات غير محفوظة', tone: ImdTone.pend) : null,
        ),
        ImdICard(
          title: 'ترويسة المستندات — يمين الصفحة',
          icon: 'file',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdLd('أسطر الجهة: الجمهورية اليمنية، وزارة الدفاع، قيادة المنطقة…'),
            for (final (i, line) in _layout.right.indexed)
              _lineEditor(
                line: line,
                enabled: w,
                onChanged: (l) => _update(_layout.copyWith(right: [..._layout.right]..[i] = l)),
                onRemove: () => _update(_layout.copyWith(right: [..._layout.right]..removeAt(i))),
                onUp: i == 0
                    ? null
                    : () => _update(_layout.copyWith(right: _moved(_layout.right, i, i - 1))),
                onDown: i == _layout.right.length - 1
                    ? null
                    : () => _update(_layout.copyWith(right: _moved(_layout.right, i, i + 1))),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImdButton.outline(
                label: 'سطر جديد',
                icon: 'plus',
                small: true,
                onPressed: w
                    ? () => _update(_layout.copyWith(
                          right: [..._layout.right, const PrintLine(text: 'سطر جديد')],
                        ))
                    : null,
              ),
            ),
          ]),
        ),
        ImdICard(
          title: 'حقول أعلى الصفحة — يسار',
          icon: 'calendar',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdLd('التاريخ، رقم القيد، رقم السند — العنوان يمينًا والقيمة يسارًا'),
            for (final (i, f) in _layout.left.indexed)
              _fieldEditor(
                field: f,
                enabled: w,
                onChanged: (v) => _update(_layout.copyWith(left: [..._layout.left]..[i] = v)),
                onRemove: () => _update(_layout.copyWith(left: [..._layout.left]..removeAt(i))),
                onUp: i == 0
                    ? null
                    : () => _update(_layout.copyWith(left: _moved(_layout.left, i, i - 1))),
                onDown: i == _layout.left.length - 1
                    ? null
                    : () => _update(_layout.copyWith(left: _moved(_layout.left, i, i + 1))),
              ),
            _addFieldButton(
              enabled: w,
              existing: _layout.left,
              onAdd: (f) => _update(_layout.copyWith(left: [..._layout.left, f])),
            ),
          ]),
        ),
        ImdICard(
          title: 'بيانات السند',
          icon: 'clipboard',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, f) in _layout.info.indexed)
              _fieldEditor(
                field: f,
                enabled: w,
                onChanged: (v) => _update(_layout.copyWith(info: [..._layout.info]..[i] = v)),
                onRemove: () => _update(_layout.copyWith(info: [..._layout.info]..removeAt(i))),
                onUp: i == 0
                    ? null
                    : () => _update(_layout.copyWith(info: _moved(_layout.info, i, i - 1))),
                onDown: i == _layout.info.length - 1
                    ? null
                    : () => _update(_layout.copyWith(info: _moved(_layout.info, i, i + 1))),
              ),
            _addFieldButton(
              enabled: w,
              existing: _layout.info,
              onAdd: (f) => _update(_layout.copyWith(info: [..._layout.info, f])),
            ),
          ]),
        ),
        ImdICard(
          title: 'جدول الأصناف',
          icon: 'package',
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            _alignPicker(
              label: 'محاذاة العناوين',
              value: _layout.table.headAlign,
              enabled: w,
              onChanged: (a) => _update(_layout.copyWith(table: _table(headAlign: a))),
            ),
            _alignPicker(
              label: 'محاذاة النص',
              value: _layout.table.cellAlign,
              enabled: w,
              onChanged: (a) => _update(_layout.copyWith(table: _table(cellAlign: a))),
            ),
            _alignPicker(
              label: 'محاذاة الأرقام',
              value: _layout.table.numAlign,
              enabled: w,
              onChanged: (a) => _update(_layout.copyWith(table: _table(numAlign: a))),
            ),
            _alignPicker(
              label: 'محاذاة عمود التسلسل',
              value: _layout.table.firstColAlign,
              enabled: w,
              onChanged: (a) => _update(_layout.copyWith(table: _table(firstColAlign: a))),
            ),
            SizedBox(
              width: 150,
              child: ImdLabeled(
                'حجم خط الجدول',
                _NumField(
                  value: _layout.table.size,
                  enabled: w,
                  onChanged: (v) => _update(_layout.copyWith(table: _table(size: v))),
                ),
                size: 11,
              ),
            ),
            // `headBold` كان يُحفظ بلا أي مفتاح يتحكم فيه.
            ImdLabeled(
              'عناوين عريضة',
              _toggle(
                icon: 'hash',
                tip: 'عريض',
                on: _layout.table.headBold,
                enabled: w,
                onTap: () => _update(
                  _layout.copyWith(table: _table(headBold: !_layout.table.headBold)),
                ),
              ),
              size: 11,
            ),
          ]),
        ),
        ImdICard(
          title: 'خط الطباعة',
          icon: 'printer',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdLd('يسري على سندات الحركة والتقارير المطبوعة — لا على الواجهة '
                '(خط الواجهة يُختار من «بيانات الجهة والمظهر»).'),
            const SizedBox(height: 10),
            ImdLabeled(
              'الخط',
              ImdSelect<String>(
                items: [for (final f in ImdPrintFonts.all) (f.family, f.label)],
                value: ImdPrintFonts.normalize(_layout.fontFamily),
                onChanged: w
                    ? (v) => _update(_layout.copyWith(fontFamily: ImdPrintFonts.normalize(v)))
                    : null,
              ),
              size: 11,
            ),
            const SizedBox(height: 6),
            Builder(builder: (ctx) {
              final font = ImdPrintFonts.of(_layout.fontFamily);
              return Text(font.note,
                  style: TextStyle(fontSize: 12, height: 1.7, color: ctx.imd.muted));
            }),
          ]),
        ),
        ImdICard(
          title: 'مربع المصادقة',
          icon: 'shield',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ImdLd('يظهر أعلى يسار سندات التوريد والعمل اليومي — أخفه إن لم '
                'تكن جهتك تشترط مصادقة قبل التوريد.'),
            _lineEditor(
              line: _layout.approval,
              enabled: w,
              onChanged: (l) => _update(_layout.copyWith(approval: l)),
              // مربع واحد لا قائمة: لا حذف ولا ترتيب.
              onRemove: () {},
              showRemove: false,
            ),
          ]),
        ),
        ImdICard(
          title: 'التوقيعات والتذييل',
          icon: 'edit',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, line) in _layout.signatures.indexed)
              _lineEditor(
                line: line,
                enabled: w,
                onChanged: (l) =>
                    _update(_layout.copyWith(signatures: [..._layout.signatures]..[i] = l)),
                onRemove: () =>
                    _update(_layout.copyWith(signatures: [..._layout.signatures]..removeAt(i))),
                onUp: i == 0
                    ? null
                    : () => _update(
                        _layout.copyWith(signatures: _moved(_layout.signatures, i, i - 1))),
                onDown: i == _layout.signatures.length - 1
                    ? null
                    : () => _update(
                        _layout.copyWith(signatures: _moved(_layout.signatures, i, i + 1))),
              ),
            _addLineButton(
              label: 'خانة توقيع جديدة',
              enabled: w,
              onAdd: () => _update(_layout.copyWith(
                signatures: [..._layout.signatures, const PrintLine(text: 'خانة توقيع')],
              )),
            ),
            const SizedBox(height: 8),
            for (final (i, line) in _layout.footer.indexed)
              _lineEditor(
                line: line,
                enabled: w,
                onChanged: (l) => _update(_layout.copyWith(footer: [..._layout.footer]..[i] = l)),
                onRemove: () => _update(_layout.copyWith(footer: [..._layout.footer]..removeAt(i))),
                onUp: i == 0
                    ? null
                    : () => _update(_layout.copyWith(footer: _moved(_layout.footer, i, i - 1))),
                onDown: i == _layout.footer.length - 1
                    ? null
                    : () => _update(_layout.copyWith(footer: _moved(_layout.footer, i, i + 1))),
              ),
            _addLineButton(
              label: 'سطر تذييل جديد',
              enabled: w,
              onAdd: () => _update(_layout.copyWith(
                footer: [..._layout.footer, const PrintLine(text: 'سطر تذييل')],
              )),
            ),
          ]),
        ),
      ],
      ),
    );
  }


  /// المفاتيح التي تُغذّيها طبقة الطباعة فعلًا (`doc.leftValues` و
  /// `doc.fieldValues`). مفتاح خارج هذه القائمة يُطبع **فارغًا** بلا أي خطأ،
  /// ولذلك يُختار من قائمة ولا يُكتب يدويًا.
  static const Map<String, String> _knownKeys = {
    'date': 'التاريخ',
    'entryNo': 'رقم القيد',
    'refNo': 'رقم السند',
    'warehouse': 'المستودع',
    'party': 'الجهة',
    'notes': 'ملاحظات',
  };

  /// زر إضافة حقل: يعرض المفاتيح غير المستعملة بعد في هذه القائمة.
  Widget _addFieldButton({
    required bool enabled,
    required List<PrintField> existing,
    required ValueChanged<PrintField> onAdd,
  }) {
    final used = existing.map((f) => f.key).toSet();
    final free = _knownKeys.entries.where((e) => !used.contains(e.key)).toList();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ImdButton.outline(
        label: free.isEmpty ? 'كل الحقول مضافة' : 'حقل جديد',
        icon: 'plus',
        small: true,
        onPressed: enabled && free.isNotEmpty
            ? () async {
                final picked = await showImdModal<String>(
                  context,
                  title: 'إضافة حقل',
                  icon: 'plus',
                  builder: (ctx) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in free)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ImdButton.outline(
                            label: e.value,
                            icon: 'clipboard',
                            onPressed: () => Navigator.of(ctx).pop(e.key),
                          ),
                        ),
                    ],
                  ),
                );
                if (picked == null) return;
                onAdd(PrintField(key: picked, label: _knownKeys[picked]!));
              }
            : null,
      ),
    );
  }

  /// زر إضافة سطر نصي (توقيع أو تذييل).
  Widget _addLineButton({
    required String label,
    required bool enabled,
    required VoidCallback onAdd,
  }) =>
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton.outline(
          label: label,
          icon: 'plus',
          small: true,
          onPressed: enabled ? onAdd : null,
        ),
      );

  TableStyle _table({
    PrintAlign? headAlign,
    PrintAlign? cellAlign,
    PrintAlign? numAlign,
    PrintAlign? firstColAlign,
    double? size,
    bool? headBold,
  }) =>
      TableStyle(
        headAlign: headAlign ?? _layout.table.headAlign,
        cellAlign: cellAlign ?? _layout.table.cellAlign,
        numAlign: numAlign ?? _layout.table.numAlign,
        firstColAlign: firstColAlign ?? _layout.table.firstColAlign,
        size: size ?? _layout.table.size,
        headBold: headBold ?? _layout.table.headBold,
      );

  /// سطر نصي في الرأس أو التذييل: النص، الحجم، المحاذاة، عريض، إظهار، حذف.
  Widget _lineEditor({
    required PrintLine line,
    required bool enabled,
    required ValueChanged<PrintLine> onChanged,
    required VoidCallback onRemove,
    VoidCallback? onUp,
    VoidCallback? onDown,
    bool showRemove = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
        SizedBox(
          width: 320,
          child: ImdLabeled(
            'النص',
            _TextField(
              value: line.text,
              enabled: enabled,
              onChanged: (v) => onChanged(line.copyWith(text: v)),
            ),
            size: 11,
          ),
        ),
        SizedBox(
          width: 110,
          child: ImdLabeled(
            'الحجم',
            _NumField(
              value: line.size,
              enabled: enabled,
              onChanged: (v) => onChanged(line.copyWith(size: v)),
            ),
            size: 11,
          ),
        ),
        _alignPicker(
          label: 'المحاذاة',
          value: line.align,
          enabled: enabled,
          onChanged: (a) => onChanged(line.copyWith(align: a)),
          width: 130,
        ),
        _toggle(
          icon: 'hash',
          tip: 'عريض',
          on: line.bold,
          enabled: enabled,
          onTap: () => onChanged(line.copyWith(bold: !line.bold)),
        ),
        _toggle(
          icon: line.show ? 'eye' : 'eraser',
          tip: line.show ? 'إخفاء' : 'إظهار',
          on: line.show,
          enabled: enabled,
          onTap: () => onChanged(line.copyWith(show: !line.show)),
        ),
        if (showRemove) ...[
          // ترتيب الأسطر: التذييل والتوقيعات تُقرأ بترتيبها على الورق.
          ImdIconButton(
            icon: 'arrow-up',
            tooltip: 'تحريك لأعلى',
            onPressed: enabled ? onUp : null,
          ),
          ImdIconButton(
            icon: 'arrow-down',
            tooltip: 'تحريك لأسفل',
            onPressed: enabled ? onDown : null,
          ),
          ImdIconButton(
            icon: 'trash',
            kind: ImdBtnKind.danger,
            tooltip: 'حذف',
            onPressed: enabled ? onRemove : null,
          ),
        ],
      ]),
    );
  }

  /// نقل عنصر داخل قائمة — يعيد نسخة جديدة ولا يمسّ الأصل.
  static List<T> _moved<T>(List<T> list, int from, int to) {
    final out = [...list];
    final item = out.removeAt(from);
    out.insert(to, item);
    return out;
  }

  /// حقل بعنوان وقيمة: محاذاة العنوان ومحاذاة القيمة وعريض وإظهار.
  Widget _fieldEditor({
    required PrintField field,
    required bool enabled,
    required ValueChanged<PrintField> onChanged,
    required VoidCallback onRemove,
    VoidCallback? onUp,
    VoidCallback? onDown,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
        SizedBox(
          width: 280,
          child: ImdLabeled(
            'عنوان الحقل',
            _TextField(
              value: field.label,
              enabled: enabled,
              onChanged: (v) => onChanged(field.copyWith(label: v)),
            ),
            size: 11,
          ),
        ),
        _alignPicker(
          label: 'العنوان',
          value: field.labelAlign,
          enabled: enabled,
          onChanged: (a) => onChanged(field.copyWith(labelAlign: a)),
          width: 130,
        ),
        _alignPicker(
          label: 'القيمة',
          value: field.valueAlign,
          enabled: enabled,
          onChanged: (a) => onChanged(field.copyWith(valueAlign: a)),
          width: 130,
        ),
        _toggle(
          icon: 'hash',
          tip: 'عريض',
          on: field.bold,
          enabled: enabled,
          onTap: () => onChanged(field.copyWith(bold: !field.bold)),
        ),
        _toggle(
          icon: field.show ? 'eye' : 'eraser',
          tip: field.show ? 'إخفاء' : 'إظهار',
          on: field.show,
          enabled: enabled,
          onTap: () => onChanged(field.copyWith(show: !field.show)),
        ),
        ImdIconButton(
          icon: 'arrow-up',
          tooltip: 'تحريك لأعلى',
          onPressed: enabled ? onUp : null,
        ),
        ImdIconButton(
          icon: 'arrow-down',
          tooltip: 'تحريك لأسفل',
          onPressed: enabled ? onDown : null,
        ),
        ImdIconButton(
          icon: 'trash',
          kind: ImdBtnKind.danger,
          tooltip: 'حذف',
          onPressed: enabled ? onRemove : null,
        ),
      ]),
    );
  }

  Widget _alignPicker({
    required String label,
    required PrintAlign value,
    required bool enabled,
    required ValueChanged<PrintAlign> onChanged,
    double width = 150,
  }) =>
      SizedBox(
        width: width,
        child: ImdLabeled(
          label,
          ImdSelect<PrintAlign>(
            dense: true,
            items: const [
              (PrintAlign.right, 'يمين'),
              (PrintAlign.center, 'وسط'),
              (PrintAlign.left, 'يسار'),
            ],
            value: value,
            onChanged: enabled ? (a) => onChanged(a ?? value) : null,
          ),
          size: 11,
        ),
      );

  /// زر تبديل صغير (عريض / إظهار) بحد ملوّن عند التفعيل.
  Widget _toggle({
    required String icon,
    required String tip,
    required bool on,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final c = context.imd;
    return Tooltip(
      message: tip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: on ? c.accentSoft : c.surface,
              border: Border.all(color: on ? c.accent : c.lineStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: ImdIcon(icon, size: 16, color: on ? c.accent : c.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// حقل نص يحتفظ بقيمته بين عمليات إعادة البناء دون فقدان موضع المؤشر.
class _TextField extends StatefulWidget {
  const _TextField({required this.value, required this.enabled, required this.onChanged});
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _ctrl = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _ctrl.text) imdSetText(_ctrl, widget.value);
  }

  @override
  Widget build(BuildContext context) =>
      ImdFld(controller: _ctrl, enabled: widget.enabled, dense: true, onChanged: widget.onChanged);
}

class _NumField extends StatefulWidget {
  const _NumField({required this.value, required this.enabled, required this.onChanged});
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final _ctrl = TextEditingController(text: _fmt(widget.value));

  static String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

  /// بدونها تبقى الأرقام القديمة عالقة في الحقل بعد «استعادة الافتراضي»
  /// أو أي تحديث خارجي للتخطيط، فيُحفظ ما يراه المستخدم مخالفًا لما في الحالة.
  @override
  void didUpdateWidget(_NumField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) imdSetText(_ctrl, _fmt(widget.value));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImdFld(
        controller: _ctrl,
        enabled: widget.enabled,
        number: true,
        dense: true,
        onChanged: (v) => widget.onChanged(double.tryParse(v.trim()) ?? widget.value),
      );
}
