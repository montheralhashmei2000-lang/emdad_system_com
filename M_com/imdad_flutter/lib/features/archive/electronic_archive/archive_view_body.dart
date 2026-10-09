part of '../electronic_archive_screen.dart';

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
              child: ArchiveImage(repo: repo, file: f, fit: BoxFit.contain),
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
            build: (_) async => repo.bytesOf(f),
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
