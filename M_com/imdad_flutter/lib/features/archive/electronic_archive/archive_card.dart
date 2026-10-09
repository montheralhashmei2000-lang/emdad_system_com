part of '../electronic_archive_screen.dart';

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
                      ? ArchiveImage(
                          repo: widget.state._repo,
                          file: f,
                          onError: (_) => _typeBadge(fg, icon),
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
