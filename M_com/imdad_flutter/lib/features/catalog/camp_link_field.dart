import 'package:flutter/material.dart';

import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';

/// حقل «🏕️ يغذي معسكر» — نقل لـ `injectCampLinkRow()` في forms-ux.js:
/// زر يعرض ملخص الاختيار ويفتح قائمة منبثقة: بحث (إذا زادت المعسكرات على ست)،
/// «جميع المعسكرات»، ثم المعسكرات، وتذييل بالعدد وزر «تم». يُغلق بالنقر خارجه أو Esc.
class CampLinkField extends StatefulWidget {
  const CampLinkField({
    super.key,
    required this.camps,
    required this.all,
    required this.ids,
    required this.onChanged,
    this.enabled = true,
  });

  final List<BeneficiaryUnit> camps;
  final bool all;
  final List<String> ids;
  final void Function(bool all, List<String> ids) onChanged;
  final bool enabled;

  @override
  State<CampLinkField> createState() => _CampLinkFieldState();
}

class _CampLinkFieldState extends State<CampLinkField> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// `campDDSummary()`
  String get _summary {
    if (widget.all) return 'جميع المعسكرات';
    final names = [for (final c in widget.camps) if (widget.ids.contains(c.id)) c.name];
    if (names.isEmpty) return 'اختر المعسكرات…';
    return names.length <= 2 ? names.join('، ') : '${names.take(2).join('، ')} +${names.length - 2}';
  }

  void _open(bool open) {
    if (open) {
      _search.clear();
      _portal.show();
    } else {
      _portal.hide();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(padding: EdgeInsetsDirectional.only(end: 6), child: ImdIcon('tent', size: 14)),
            ),
            const TextSpan(text: 'يغذي معسكر '),
            TextSpan(
              text: '(يتيح ربط المستودع بالصرف/التحويل تلقائيًا)',
              style: TextStyle(fontWeight: FontWeight.w400, color: c.muted),
            ),
          ]),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text2),
        ),
        const SizedBox(height: 6),
        CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (ctx) => _popup(ctx),
            child: MouseRegion(
              cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: GestureDetector(
                onTap: widget.enabled ? () => _open(!_portal.isShowing) : null,
                child: Container(
                  constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.enabled ? c.surface : c.bg,
                    border: Border.all(color: _portal.isShowing ? c.accent : c.lineStrong),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(_summary,
                          overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.text)),
                    ),
                    AnimatedRotation(
                      turns: _portal.isShowing ? .5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: ImdIcon('chevron-down', size: 14, color: c.muted),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        const ImdNote('سيظهر المستودع في الصرف والتحويل فقط عندما يكون مسموحًا لمعسكر الجهة المستفيدة.'),
      ],
    );
  }

  Widget _popup(BuildContext ctx) {
    final c = ctx.imd;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 320;
    return Stack(children: [
      // إغلاق عند النقر خارج القائمة
      Positioned.fill(
        child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => _open(false)),
      ),
      CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 4),
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e.logicalKey.keyLabel == 'Escape') {
              _open(false);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Material(
            color: Colors.transparent,
            child: StatefulBuilder(builder: (ctx, setPop) {
              final q = _search.text.trim();
              final list = [
                for (final camp in widget.camps)
                  if (q.isEmpty || '${camp.code.isNotEmpty ? '${camp.code}-' : ''}${camp.name}'.contains(q)) camp
              ];
              void set(bool all, List<String> ids) {
                widget.onChanged(all, ids);
                setPop(() {});
                setState(() {});
              }

              return Container(
                width: width,
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.isDark ? const Color(0xFF2C3B35) : const Color(0xFFCFDCD6)),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [BoxShadow(color: Color(0x2E0F281E), blurRadius: 28, offset: Offset(0, 10))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (widget.camps.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (_) => setPop(() {}),
                        style: TextStyle(fontSize: 14, color: c.text),
                        decoration: imdFieldDecoration(ctx, hint: 'بحث عن معسكر', dense: true),
                      ),
                    ),
                  _opt(ctx, 'جميع المعسكرات', widget.all, (v) => set(v, v ? [] : widget.ids), bold: true),
                  Flexible(
                    child: widget.camps.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('لا توجد معسكرات بعد — أضف المعسكرات أولًا من شاشة الوحدات',
                                style: TextStyle(fontSize: 12, color: Color(0xFF98A8A0))),
                          )
                        : list.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: Text('لا نتائج مطابقة', style: TextStyle(fontSize: 12, color: Color(0xFF98A8A0))),
                              )
                            : ListView(shrinkWrap: true, children: [
                                for (final camp in list)
                                  _opt(
                                    ctx,
                                    '${camp.code.isNotEmpty ? '${camp.code}-' : ''}${camp.name}',
                                    !widget.all && widget.ids.contains(camp.id),
                                    (v) {
                                      final ids = [...widget.ids];
                                      if (v && !ids.contains(camp.id)) ids.add(camp.id);
                                      if (!v) ids.remove(camp.id);
                                      set(false, ids);
                                    },
                                  ),
                              ]),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
                    child: Row(children: [
                      Text(widget.all ? 'كل المعسكرات' : '${nf(widget.ids.length)} محدد',
                          style: TextStyle(fontSize: 12, color: c.muted)),
                      const Spacer(),
                      ImdButton(label: 'تم', small: true, onPressed: () => _open(false)),
                    ]),
                  ),
                ]),
              );
            }),
          ),
        ),
      ),
    ]);
  }

  Widget _opt(BuildContext ctx, String label, bool checked, ValueChanged<bool> onTap, {bool bold = false}) {
    final c = ctx.imd;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onTap(!checked),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: bold
            ? BoxDecoration(border: Border(bottom: BorderSide(color: c.line)))
            : null,
        margin: bold ? const EdgeInsets.only(bottom: 4) : null,
        child: Row(children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Checkbox(value: checked, activeColor: c.accent, onChanged: (v) => onTap(v ?? false)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: c.text, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
        ]),
      ),
    );
  }
}
