part of '../electronic_archive_screen.dart';

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
