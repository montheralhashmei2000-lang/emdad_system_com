import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../core/ui/imd_form.dart';

import '../../core/ui/imd_format.dart';
import '../../core/ui/imd_icon.dart';
import '../../core/ui/imd_layout.dart';
import '../../core/ui/imd_scan.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';

// عناصر شاشات المستندات المخزنية (الاستلام، الصرف، التحويل، المرتجعات) — نفس أصناف CSS في الويب:
// .soft-card، .workflow-steps، .quick-grid، .print-tip، .bcinput، .rvrow/.rgrid، منتقي الأصناف (item-picker.js)،
// صندوق الفحص السريع (paintValidationBox)، الشريط الثابت (.sticky-actions)، وبطاقات المستندات (.dcard).

/// `.soft-card`
class ImdSoftCard extends StatelessWidget {
  const ImdSoftCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: ImdBp.of(context).mobile ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: child,
    );
  }
}

/// `.workflow-steps > .wstep`
class ImdWorkflowSteps extends StatelessWidget {
  const ImdWorkflowSteps(this.steps, {super.key});
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < steps.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${i + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: c.accent)),
                TextSpan(text: ' ${steps[i]}'),
              ]),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.text2, height: 1.6),
            ),
          ),
      ]),
    );
  }
}

/// `.quick-grid > .qcard` — auto-fit بحد أدنى 170.
class ImdQuickGrid extends StatelessWidget {
  const ImdQuickGrid(this.cards, {super.key});
  final List<(String, String)> cards;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(builder: (context, cons) {
        const gap = 10.0;
        // auto-fit يطوي المسارات الفارغة فتتمدد البطاقات على كامل العرض.
        final cols = ((cons.maxWidth + gap) / (170 + gap)).floor().clamp(1, cards.isEmpty ? 1 : cards.length);
        final children = [
          for (final (l, v) in cards)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(ImdSizes.radius),
                boxShadow: imdShadow(c),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.muted, height: 1.6)),
                const SizedBox(height: 6),
                Text(v, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: c.text, height: 1.6)),
              ]),
            ),
        ];
        return ImdGridRows(cols: cols, gap: gap, children: children);
      }),
    );
  }
}

/// `.print-tip`
class ImdPrintTip extends StatelessWidget {
  const ImdPrintTip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.infoSoft,
        border: Border.all(color: c.isDark ? const Color(0x5984ADFF) : const Color(0xFFB2CCFF)),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.6,
              color: c.isDark ? const Color(0xFFB2CCFF) : const Color(0xFF1849A9))),
    );
  }
}

/// `input.fld.bcinput` + زر الكاميرا (يُضاف تحته كما يفعل forms-ux.js).
class ImdBarcodeInput extends StatefulWidget {
  const ImdBarcodeInput({super.key, required this.hint, required this.onSubmit});
  final String hint;
  final ValueChanged<String> onSubmit;

  @override
  State<ImdBarcodeInput> createState() => _ImdBarcodeInputState();
}

class _ImdBarcodeInputState extends State<ImdBarcodeInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(String v) {
    final code = v.trim();
    if (code.isEmpty) return;
    _ctrl.clear();
    _focus.requestFocus();
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    OutlineInputBorder b(double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.accent, width: w),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // الإطار المتقطع يُرسم فوق الحقل (Flutter لا يدعم حدودًا متقطعة للحقول).
      CustomPaint(
        foregroundPainter: _DashedRRect(c.accent),
        child: TextField(
          controller: _ctrl,
          focusNode: _focus,
          onSubmitted: _go,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            hintStyle: TextStyle(color: c.faint, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1),
            filled: true,
            fillColor: c.accentSoft,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: b(0).copyWith(borderSide: BorderSide.none),
            enabledBorder: b(0).copyWith(borderSide: BorderSide.none),
            focusedBorder: b(1.5),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ImdButton.outline(
          label: '',
          icon: 'camera',
          small: true,
          onPressed: () async {
            final v = await ImdScanner.scan(context);
            if (v != null) _go(v);
          },
        ),
      ),
    ]);
  }
}

class _DashedRRect extends CustomPainter {
  _DashedRRect(this.color, [this.radius = 10, this.width = 1.5]);
  final double radius;
  final double width;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(width / 2);
    final path = Path()..addRRect(rr);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRect old) => old.color != color;
}

/// منتقي الصنف بالكتابة — نقل لـ item-picker.js: بحث بالاسم أو الكود مع توحيد الحروف العربية،
/// قائمة منسدلة بحد 60 نتيجة (الاسم + الكود صغيرًا)، أسهم وEnter وEsc.
class ImdItemPicker extends StatefulWidget {
  const ImdItemPicker({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.labelOf,
  });

  final List<Item> items;
  final String value;
  final ValueChanged<String> onChanged;

  /// نص الخيار «الكود — الاسم» (قد يُضاف الرصيد كما في شاشة الصرف).
  final String Function(Item)? labelOf;

  @override
  State<ImdItemPicker> createState() => _ImdItemPickerState();
}

class _ImdItemPickerState extends State<ImdItemPicker> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _listScroll = ScrollController();
  int _idx = -1;
  List<Item> _rows = const [];

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp('[ً-ْ]'), '')
      .trim();

  String _label(Item i) => widget.labelOf?.call(i) ?? '${i.code} — ${i.name}';

  Item? get _selected => widget.items.where((x) => x.id == widget.value).firstOrNull;

  @override
  void initState() {
    super.initState();
    _sync();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _open(_ctrl.text == (_selected == null ? '' : _label(_selected!)) ? '' : _ctrl.text);
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted || _focus.hasFocus) return;
          _close();
          _sync();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant ImdItemPicker old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value || old.items != widget.items) _sync();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  void _sync() {
    final s = _selected;
    imdSetText(_ctrl, s == null ? '' : _label(s));
  }

  void _open(String q) {
    final nq = norm(q);
    _rows = (nq.isEmpty ? widget.items : widget.items.where((i) => norm(_label(i)).contains(nq))).take(60).toList();
    _idx = -1;
    if (!_portal.isShowing) _portal.show();
    setState(() {});
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
    _idx = -1;
    if (mounted) setState(() {});
  }

  void _pick(Item i) {
    widget.onChanged(i.id);
    imdSetText(_ctrl, _label(i));
    _close();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown || e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (!_portal.isShowing) _open(_ctrl.text);
      setState(() {
        _idx = (_idx + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, _rows.isEmpty ? 0 : _rows.length - 1);
      });
      if (_listScroll.hasClients) _listScroll.jumpTo((_idx * 38.0).clamp(0, _listScroll.position.maxScrollExtent));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && _portal.isShowing && _rows.isNotEmpty) {
      _pick(_rows[_idx >= 0 ? _idx : 0]);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      _sync();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (ctx) {
          final box = context.findRenderObject() as RenderBox?;
          return CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 2),
            child: Align(
              alignment: Alignment.topRight,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: box?.size.width ?? 300,
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [BoxShadow(color: Color(0x24101828), blurRadius: 28, offset: Offset(0, 12))],
                  ),
                  child: _rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text('لا توجد أصناف مطابقة', style: TextStyle(fontSize: 13, color: c.muted)),
                        )
                      : ListView.builder(
                          controller: _listScroll,
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _rows.length,
                          itemBuilder: (ctx, i) {
                            final it = _rows[i];
                            final parts = _label(it).split('—');
                            final name = (parts.length > 1 ? parts.sublist(1).join('—') : _label(it)).trim();
                            final code = parts.length > 1 ? parts.first.trim() : '';
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) => setState(() => _idx = i),
                              child: GestureDetector(
                                onTapDown: (_) => _pick(it),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: i == _idx ? c.accentSoft : null,
                                    border: i == _rows.length - 1 ? null : Border(bottom: BorderSide(color: c.line)),
                                  ),
                                  child: Row(children: [
                                    Expanded(child: Text(name, style: TextStyle(fontSize: 13.5, color: c.text))),
                                    if (code.isNotEmpty) Text(code, style: TextStyle(fontSize: 11.5, color: c.muted)),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          );
        },
        child: Focus(
          onKeyEvent: _key,
          canRequestFocus: false,
          skipTraversal: true,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            onChanged: _open,
            style: TextStyle(fontSize: 14, color: c.text),
            decoration: imdFieldDecoration(context, hint: 'اكتب اسم الصنف أو الكود…').copyWith(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
        ),
      ),
    );
  }
}

/// عنوان حقل صغير داخل صفوف الأصناف (`label style="font-size:11px"` بحد أدنى 15 وهامش 4).
class ImdRowLabel extends StatelessWidget {
  const ImdRowLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.imd.text2, height: 1.6)),
      );
}

/// `.rvrow` — بطاقة سطر صنف: كتلة واحدة تجمع كل بيانات الصنف.
///
/// [index] رقم السطر يُعرض في زاويته، و[trailing] سطر معلومات أسفله (مكافئ
/// الكمية بالوحدة الأساسية مثلًا). الترقيم يفصل الأصناف بصريًا حين تكثر، وقد
/// صار ألزم بعد أن صارت الأسطر تُجمَّع وتُعاد توزيعها تلقائيًا.
class ImdRvRow extends StatelessWidget {
  const ImdRvRow({super.key, required this.child, this.index, this.trailing});

  final Widget child;
  final int? index;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (index == null)
          child
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10, top: 20),
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  nf(index!.toDouble()),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: c.accent),
                ),
              ),
            ),
            Expanded(child: child),
          ]),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// `.rmeta`
class ImdRowMeta extends StatelessWidget {
  const ImdRowMeta(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 16),
          child: ImdEmojiText(text,
              iconSize: 12, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: context.imd.muted)),
        ),
      );
}

/// `.cy` — صندوق عملية الأصناف القابلة للتعبئة.
class ImdCyBox extends StatelessWidget {
  const ImdCyBox({super.key, required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: c.noteBg,
        border: Border.all(color: c.noteBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ImdEmojiText(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.noteText)),
        SizedBox(width: 180, child: ImdSelect<String>(value: value, items: options, onChanged: (v) => onChanged(v ?? value))),
      ]),
    );
  }
}

/// عنصر فحص (`paintValidationBox`).
class ImdCheck {
  const ImdCheck(this.level, this.title, this.desc);
  final String level; // ok | warn | err
  final String title;
  final String desc;
}

/// `paintValidationBox(elId, title, items)`
class ImdValidationBox extends StatelessWidget {
  const ImdValidationBox({super.key, required this.title, required this.items});
  final String title;
  final List<ImdCheck> items;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    if (items.isEmpty) {
      return ImdSoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ImdEmojiText('✅ $title', style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
          ),
          Text('لا توجد ملاحظات حرجة حاليًا — تقدر تكمل بثقة.', style: TextStyle(fontSize: 12.5, color: c.muted)),
        ]),
      );
    }
    return ImdSoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: c.text)),
        ),
        ImdStatusList(items: [
          for (final it in items) (it.level == 'err' ? 'err' : (it.level == 'warn' ? 'warn' : ''), it.title, it.desc),
        ]),
      ]),
    );
  }
}

/// `.sticky-actions` — شريط الإجراءات (يلتصق بأسفل الشاشة عبر `ImdStickyPage`).
class ImdStickyActions extends StatelessWidget {
  const ImdStickyActions({super.key, required this.children, this.caption});
  final List<Widget> children;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: .96),
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: c.isDark ? const Color(0x80000000) : const Color(0x14101828),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children),
        // `.action-caption{margin-inline-start:auto}` يدفع التنبيه إلى الطرف الآخر من السطر.
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(caption!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.muted)),
            ),
          ),
      ]),
    );
  }
}

/// صفحة بمحتوى قابل للتمرير وشريط إجراءات ملتصق بالأسفل كـ `position: sticky; bottom: 12px`:
/// يظهر ملتصقًا ما دام موضعه الطبيعي تحت حافة الشاشة، ويعود لمكانه عند الوصول إليه.
class ImdStickyPage extends StatefulWidget {
  const ImdStickyPage({super.key, required this.children, required this.sticky, this.after = const []});
  final List<Widget> children;
  final Widget sticky;

  /// عناصر بعد الشريط (نادرًا).
  final List<Widget> after;

  @override
  State<ImdStickyPage> createState() => _ImdStickyPageState();
}

class _ImdStickyPageState extends State<ImdStickyPage> {
  final _scroll = ScrollController();
  final _inlineKey = GlobalKey();
  final _viewKey = GlobalKey();
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// القياس ممنوع أثناء مرحلة التخطيط (إشعار تغيّر الحجم يصل داخلها)،
  /// فيؤجَّل إلى ما بعد الإطار وإلا رمى الإطار «RenderBox.size accessed beyond scope».
  void _check() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measure();
      });
      return;
    }
    _measure();
  }

  void _measure() {
    final inline = _inlineKey.currentContext?.findRenderObject() as RenderBox?;
    final view = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (inline == null || view == null || !inline.attached || !view.attached) return;
    final bottom = inline.localToGlobal(Offset(0, inline.size.height), ancestor: view).dy;
    final pinned = bottom > view.size.height - 12 + .5;
    if (pinned != _pinned) setState(() => _pinned = pinned);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check();
    });
    final pad = ImdPage.paddingOf(context);
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _check();
        return false;
      },
      child: Stack(key: _viewKey, children: [
        SingleChildScrollView(
          controller: _scroll,
          padding: pad,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...widget.children,
            const SizedBox(height: 10),
            Opacity(opacity: _pinned ? 0 : 1, child: KeyedSubtree(key: _inlineKey, child: widget.sticky)),
            ...widget.after,
          ]),
        ),
        if (_pinned)
          Positioned(left: pad.left, right: pad.right, bottom: 12, child: widget.sticky),
      ]),
    );
  }
}

/// `.dcard` — بطاقة مستند (مسودة/أمر/سند) برأس `.dh`.
class ImdDocCard extends StatelessWidget {
  const ImdDocCard({super.key, required this.head, this.body, this.actions});
  final List<Widget> head;
  final Widget? body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(ImdSizes.radius),
        boxShadow: imdShadow(c),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: head),
        if (body != null) Padding(padding: const EdgeInsets.only(top: 8), child: body),
        if (actions != null && actions!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: ImdRbar(bottom: 0, children: actions!)),
      ]),
    );
  }
}

/// مستودع بأيقونة صغيرة في رأس البطاقة (`<span style="color:var(--mut);font-size:12px">🏬 …</span>`).
class ImdDocWarehouse extends StatelessWidget {
  const ImdDocWarehouse(this.name, {super.key, this.icon = 'warehouse'});
  final String name;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ImdIcon(icon, size: 13, color: c.muted),
      const SizedBox(width: 4),
      Text(name, style: TextStyle(color: c.muted, fontSize: 12)),
    ]);
  }
}

/// نص أصناف المستند: «اسم <b>كمية</b> وحدة · …».
class ImdDocLines extends StatelessWidget {
  const ImdDocLines(this.lines, {super.key, this.qtyColor, this.negative = false});
  final List<(String name, double qty, String unit)> lines;
  final Color? qtyColor;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const TextSpan(text: ' · '),
          TextSpan(text: '${lines[i].$1} '),
          TextSpan(
            text: '${negative ? '-' : ''}${nf(lines[i].$2)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: qtyColor),
          ),
          TextSpan(text: ' ${lines[i].$3}'),
        ],
      ]),
      style: TextStyle(fontSize: 13, height: 1.9, color: c.text),
    );
  }
}

/// الوقت الحالي بتاريخ اليوم المحلي (`todayISO()`).
String imdToday() => isoDay(DateTime.now());

/// `isFutureDate(v)`
bool imdIsFuture(String v) => v.isNotEmpty && v.compareTo(imdToday()) > 0;

/// `duplicateCountBy(rows, keyFn)`
int imdDuplicateCount<T>(List<T> rows, String Function(T) key) {
  final m = <String, int>{};
  for (final r in rows) {
    final k = key(r);
    if (k.isEmpty) continue;
    m[k] = (m[k] ?? 0) + 1;
  }
  return m.values.where((v) => v > 1).length;
}

/// `.target-pills` — مقاطع نوع التوجيه (الزر النشط أبيض بظل خفيف).
class ImdTargetPills<T> extends StatelessWidget {
  const ImdTargetPills({super.key, required this.tabs, required this.value, required this.onChanged});
  final List<ImdTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(builder: (context, cons) {
        // flex:1 بحد أدنى 90 مع التفاف
        final perRow = ((cons.maxWidth + 6) / (90 + 6)).floor().clamp(1, tabs.length);
        final rows = <Widget>[];
        for (var i = 0; i < tabs.length; i += perRow) {
          final slice = tabs.sublist(i, (i + perRow).clamp(0, tabs.length));
          if (i > 0) rows.add(const SizedBox(height: 6));
          rows.add(Row(children: [
            for (var j = 0; j < slice.length; j++) ...[
              if (j > 0) const SizedBox(width: 6),
              Expanded(child: _pill(context, slice[j])),
            ],
          ]));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: rows);
      }),
    );
  }

  Widget _pill(BuildContext context, ImdTab<T> t) {
    final c = context.imd;
    final on = t.value == value;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(t.value),
        child: Container(
          constraints: BoxConstraints(minHeight: ImdSizes.touchMin),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: on ? const [BoxShadow(color: Color(0x1A101828), blurRadius: 3, offset: Offset(0, 1))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (t.icon != null) ...[ImdIcon(t.icon!, size: 14, color: on ? c.text : c.text2), const SizedBox(width: 6)],
            Flexible(
              child: Text(t.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: on ? c.text : c.text2)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// حقل للقراءة فقط بخلفية مخصصة (`readonly style="background:…;font-weight:…"`).
class ImdReadonlyField extends StatelessWidget {
  const ImdReadonlyField({super.key, required this.text, this.bg, this.color, this.weight = FontWeight.w900});
  final String text;
  final Color? bg;
  final Color? color;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return InputDecorator(
      decoration: imdFieldDecoration(context).copyWith(fillColor: bg ?? (c.isDark ? c.bg : const Color(0xFFEEF1EE))),
      child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: weight, color: color ?? c.muted)),
    );
  }
}

/// صندوق بإطار متقطع (`border:1px dashed var(--line)`) — منطقة القوة في شاشة الصرف.
class ImdDashedBox extends StatelessWidget {
  const ImdDashedBox({super.key, required this.child, this.color, this.radius = 10, this.padding = const EdgeInsets.all(10), this.background});
  final Widget child;
  final Color? color;
  final double radius;
  final EdgeInsets padding;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return CustomPaint(
      foregroundPainter: _DashedRRect(color ?? c.line, radius, 1),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: background ?? (c.isDark ? c.bg : const Color(0xFFF7FAF8)),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}
