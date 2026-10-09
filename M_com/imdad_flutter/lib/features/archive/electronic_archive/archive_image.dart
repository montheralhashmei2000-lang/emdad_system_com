import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/ui/imd_form.dart';
import '../../../core/ui/widgets/imd_chips.dart';
import '../../../data/db/app_database.dart';
import '../../../data/repos/archive_repo.dart';

/// صورةُ ملفٍ مؤرشف.
///
/// `Image.file` لا تصلح بعد تشفير المرفقات: محمّلُ الصور يقرأ الملف بنفسه
/// فيرى بايتاتٍ مشفَّرة. فتُقرأ البايتات عبر [ArchiveRepo.bytesOf] (تفكّ
/// المشفَّر وتُعيد الصريح القديم كما هو) ثم تُعرض من الذاكرة.
class ArchiveImage extends StatefulWidget {
  const ArchiveImage({
    super.key,
    required this.repo,
    required this.file,
    this.fit = BoxFit.cover,
    this.onError,
  });

  final ArchiveRepo repo;
  final ArchiveFile file;
  final BoxFit fit;

  /// ما يُعرض إن تعذّرت القراءة أو فكّ التشفير.
  final WidgetBuilder? onError;

  @override
  State<ArchiveImage> createState() => _ArchiveImageState();
}

class _ArchiveImageState extends State<ArchiveImage> {
  late Future<Uint8List> _bytes = widget.repo.bytesOf(widget.file);

  @override
  void didUpdateWidget(ArchiveImage old) {
    super.didUpdateWidget(old);
    if (old.file.storedPath != widget.file.storedPath) {
      _bytes = widget.repo.bytesOf(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasError) return _fallback(context);
        final data = snap.data;
        if (data == null) return const Center(child: ImdLd('جارٍ فتح الملف…'));
        return Image.memory(
          data,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _fallback(context),
        );
      },
    );
  }

  Widget _fallback(BuildContext context) =>
      widget.onError?.call(context) ??
      const ImdNote('تعذّر عرض الصورة — نزّل نسخةً وافتحها خارجيًّا.');
}
