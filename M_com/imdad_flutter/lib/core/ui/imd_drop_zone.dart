import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import 'imd_icon.dart';
import 'imd_tokens.dart';
import 'imd_window.dart';

/// منطقة إفلات ملفاتٍ من مستكشف ويندوز فوق [child].
///
/// تفعل شيئًا على ويندوز وحده ([ImdWindow.supported])؛ على أندرويد وفي
/// الاختبارات تُرجع [child] كما هو بلا أي غلاف، فلا أثر لها هناك.
///
/// الملفات المُفلَتة تُرشَّح بالامتداد [extensions] (بلا نقطة، بأحرفٍ صغيرة)
/// ويُسلَّم المسار الأول المطابق إلى [onFile]. وفوق المحتوى يظهر غطاءٌ بنص
/// [hint] ما دام ملفٌّ معلّقٌ فوق المنطقة، فيعرف المستخدم أن الإفلات مقبول.
class ImdDropZone extends StatefulWidget {
  const ImdDropZone({
    super.key,
    required this.extensions,
    required this.onFile,
    required this.child,
    this.hint = 'أفلت الملف هنا',
    this.enabled = true,
  });

  final List<String> extensions;
  final ValueChanged<String> onFile;
  final Widget child;
  final String hint;
  final bool enabled;

  /// امتداد المسار بأحرفٍ صغيرة بلا نقطة — أو فارغ إن لم يكن له امتداد.
  static String extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// أول مسارٍ بامتدادٍ مقبول، أو `null`.
  static String? firstMatching(Iterable<String> paths, List<String> extensions) {
    for (final p in paths) {
      if (extensions.contains(extensionOf(p))) return p;
    }
    return null;
  }

  @override
  State<ImdDropZone> createState() => _ImdDropZoneState();
}

class _ImdDropZoneState extends State<ImdDropZone> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    if (!ImdWindow.supported || !widget.enabled) return widget.child;
    final c = context.imd;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (d) {
        setState(() => _over = false);
        final path = ImdDropZone.firstMatching(d.files.map((f) => f.path), widget.extensions);
        if (path != null) widget.onFile(path);
      },
      child: Stack(
        children: [
          widget.child,
          if (_over)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.accentSoft.withValues(alpha: .92),
                    border: Border.all(color: c.accent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ImdIcon('arrow-down', size: 28, color: c.accent),
                    const SizedBox(height: 8),
                    Text(widget.hint,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.accent)),
                    const SizedBox(height: 4),
                    Text(widget.extensions.map((e) => '.$e').join('  '),
                        style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
