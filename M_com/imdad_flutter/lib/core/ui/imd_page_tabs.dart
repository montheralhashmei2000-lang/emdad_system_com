import 'package:flutter/material.dart';

import 'imd_context_menu.dart';
import 'imd_icon.dart';
import 'imd_status_bar.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// تبويبةٌ لصفحةٍ مفتوحة في القشرة.
class ImdOpenPage {
  const ImdOpenPage({required this.id, required this.title, this.icon, this.stale = false});

  final String id;
  final String title;
  final String? icon;

  /// تغيّرت البيانات من صفحةٍ أخرى منذ أُخفيت هذه — قد تعرض أرقامًا قديمة.
  final bool stale;
}

/// شريط الصفحات المفتوحة (سطح المكتب): تبويبٌ لكل صفحة، ونقرةٌ للتنقّل، و×
/// للإغلاق. الصفحات المخفيّة تبقى حيّةً بحالتها فلا يضيع نموذجٌ نصف مملوء.
class ImdPageTabs extends StatelessWidget {
  const ImdPageTabs({
    super.key,
    required this.pages,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    this.onCloseOthers,
  });

  final List<ImdOpenPage> pages;
  final String activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final ValueChanged<String>? onCloseOthers;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: c.tableHead,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final p in pages)
              _Tab(
                page: p,
                active: p.id == activeId,
                closable: pages.length > 1,
                onTap: () => onSelect(p.id),
                onClose: () => onClose(p.id),
                onCloseOthers: onCloseOthers == null || pages.length < 2 ? null : () => onCloseOthers!(p.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.page,
    required this.active,
    required this.closable,
    required this.onTap,
    required this.onClose,
    this.onCloseOthers,
  });

  final ImdOpenPage page;
  final bool active;
  final bool closable;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final active = widget.active;
    final fg = active ? c.text : c.muted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: ImdCursor.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        // زرّ الفأرة الأوسط يغلق التبويبة كما في المتصفحات.
        onTertiaryTapUp: widget.closable ? (_) => widget.onClose() : null,
        onSecondaryTapDown: widget.onCloseOthers == null
            ? null
            : (d) => showImdContextMenu(context, d.globalPosition, [
                  ImdMenuItem(label: 'إغلاق', icon: 'x', onTap: widget.onClose, enabled: widget.closable),
                  ImdMenuItem(label: 'إغلاق الباقي', onTap: widget.onCloseOthers!),
                ]),
        child: Container(
          margin: const EdgeInsets.only(top: 5, left: 2, right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          constraints: const BoxConstraints(maxWidth: 220),
          decoration: BoxDecoration(
            color: active ? c.surface : (_hover ? c.hover : null),
            border: Border(
              top: BorderSide(color: active ? c.accent : Colors.transparent, width: 2),
              left: BorderSide(color: active ? c.line : Colors.transparent),
              right: BorderSide(color: active ? c.line : Colors.transparent),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.page.icon != null) ...[
              ImdIcon(widget.page.icon!, size: 13, color: active ? c.accent : c.muted),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                widget.page.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: fg),
              ),
            ),
            if (widget.page.stale) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'تغيّرت البيانات منذ فتحتَ هذه الصفحة',
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: c.warn, shape: BoxShape.circle)),
              ),
            ],
            if (widget.closable) ...[
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: widget.onClose,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ImdIcon('x', size: 11, color: (active || _hover) ? c.muted : c.faint),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// يستضيف صفحةً مفتوحة: تبقى مبنيّةً بحالتها وإن لم تكن الظاهرة.
///
/// - `Offstage`: لا تخطيط ولا رسم للمخفيّة، فعشر صفحاتٍ مفتوحة لا تكلّف
///   تخطيط عشر شاشات في كل إطار.
/// - `TickerMode`: لا تحريكات (shimmer ومؤشرات) تعمل خلف الستار.
/// - `ExcludeFocus`: لا يهبط Tab على حقلٍ في صفحةٍ لا يراها المستخدم.
/// - `PrimaryScrollController.none`: كل صفحةٍ تقرأ تمريرها الخاص؛ فشاشاتٌ
///   كثيرة بتمريرٍ رأسيٍّ افتراضيٍّ لو شاركت متحكّمًا واحدًا لتعطّل التمرير
///   («ScrollController attached to multiple scroll views»).
class ImdPageHost extends StatelessWidget {
  const ImdPageHost({super.key, required this.active, required this.sink, required this.child});

  final bool active;
  final ImdRecordSink sink;
  final Widget child;

  @override
  Widget build(BuildContext context) => Offstage(
        offstage: !active,
        child: TickerMode(
          enabled: active,
          child: ExcludeFocus(
            excluding: !active,
            child: PrimaryScrollController.none(
              child: ImdRecordScope(sink: sink, child: child),
            ),
          ),
        ),
      );
}

/// شريطٌ ناعمٌ فوق الصفحة الظاهرة حين تكون بياناتها قد تقادمت.
///
/// لا يُعاد تحميل الصفحة تلقائيًّا: قد يكون فيها سندٌ نصف مملوء، وإعادة البناء
/// تمحوه. فالقرار للمستخدم.
class ImdStaleBanner extends StatelessWidget {
  const ImdStaleBanner({super.key, required this.onRefresh, required this.onDismiss});

  final VoidCallback onRefresh;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.warnSoft,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(children: [
        ImdIcon('alert', size: 14, color: c.warn),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'تغيّرت بيانات النظام من صفحةٍ أخرى — قد يعرض هذا الجدول أرقامًا قديمة.',
            style: TextStyle(fontSize: 12.5, color: c.text2),
          ),
        ),
        ImdButton.outline(label: 'تحديث الصفحة', icon: 'refresh', small: true, onPressed: onRefresh),
        const SizedBox(width: 6),
        ImdIconButton(icon: 'x', tooltip: 'إخفاء', onPressed: onDismiss),
      ]),
    );
  }
}
