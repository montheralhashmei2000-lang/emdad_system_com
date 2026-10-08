part of '../electronic_archive_screen.dart';

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
      if (!mounted) return;
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
