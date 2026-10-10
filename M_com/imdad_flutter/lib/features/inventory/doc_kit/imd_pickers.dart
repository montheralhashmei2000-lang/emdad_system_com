import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/ui/imd_form.dart';
import '../../../core/ui/imd_page_dirty.dart';
import '../../../core/ui/imd_tokens.dart';
import '../../../core/ui/imd_widgets.dart';
import '../../../data/db/app_database.dart';


/// حقلٌ يُكتب فيه أو يُختار من قائمةٍ منسدلة — نصوصٌ بسيطة لا كائنات.
///
/// يتقاسم عقد التفاعل مع [ImdItemPicker] حرفيًّا (كتابةٌ تُصفّي، أسهمٌ
/// وEnter وEsc، إغلاقٌ بفقد التركيز)، ومعه الاحترازان نفساهما: الإبراز
/// عبر `ValueNotifier` لا `setState` (نداء المرور يقع في
/// `postFrameCallbacks`)، وعرض القائمة من `LayerLink.leaderSize` لا من
/// قراءة تخطيطٍ أثناء البناء.
class ImdTypeAhead extends StatefulWidget {
  const ImdTypeAhead({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint,
    this.empty = 'لا نتائج',
  });

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String empty;

  @override
  State<ImdTypeAhead> createState() => _ImdTypeAheadState();
}


class _ImdTypeAheadState extends State<ImdTypeAhead> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _idx = ValueNotifier<int>(-1);
  List<String> _rows = const [];

  @override
  void initState() {
    super.initState();
    _sync();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _open('');
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
  void didUpdateWidget(covariant ImdTypeAhead old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value || old.options != widget.options) _sync();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _idx.dispose();
    super.dispose();
  }

  void _sync() => imdSetText(_ctrl, widget.value);

  void _open(String q) {
    if (!mounted) return;
    final nq = _ImdItemPickerState.norm(q);
    _rows = nq.isEmpty
        ? widget.options
        : widget.options.where((o) => _ImdItemPickerState.norm(o).contains(nq)).toList();
    _idx.value = -1;
    if (!_portal.isShowing) _portal.show();
    setState(() {});
  }

  void _close() {
    if (!mounted) return;
    if (_portal.isShowing) _portal.hide();
    _idx.value = -1;
    setState(() {});
  }

  void _pick(String v) {
    if (!mounted) return;
    widget.onChanged(v);
    imdSetText(_ctrl, v);
    _close();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
        e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (!_portal.isShowing) _open(_ctrl.text);
      _idx.value = (_idx.value + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1))
          .clamp(0, _rows.isEmpty ? 0 : _rows.length - 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && _portal.isShowing && _rows.isNotEmpty) {
      _pick(_rows[_idx.value >= 0 ? _idx.value : 0]);
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
        overlayChildBuilder: (ctx) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 2),
          child: Align(
            alignment: Alignment.topRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: _link.leaderSize?.width ?? 160,
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: imdShadowOverlay(c),
                ),
                child: _rows.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(widget.empty, style: TextStyle(fontSize: 12, color: c.muted)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _rows.length,
                        itemBuilder: (ctx, i) => MouseRegion(
                          cursor: ImdCursor.click,
                          onEnter: (_) => _idx.value = i,
                          child: GestureDetector(
                            onTapDown: (_) => _pick(_rows[i]),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _idx,
                              builder: (context, idx, child) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: i == idx ? c.accentSoft : null,
                                  border: i == _rows.length - 1
                                      ? null
                                      : Border(bottom: BorderSide(color: c.line)),
                                ),
                                child: child,
                              ),
                              child: Text(_rows[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: c.text)),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: ImdCompact.of(context)
                  ? ImdSizes.compactField
                  : ImdSizes.touchMin),
          child: Focus(
            onKeyEvent: _key,
            canRequestFocus: false,
            skipTraversal: true,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onChanged: _open,
              style: TextStyle(fontSize: ImdCompact.of(context) ? 13 : 14, color: c.text),
              decoration: imdFieldDecoration(context, hint: widget.hint),
            ),
          ),
        ),
      ),
    );
  }
}


/// منتقي وحدة القياس: يُكتب أو يُختار.
///
/// كانت قائمةً منسدلة وحدها، فمن يعرف وحدته يفتح القائمة ويبحث عنها بعينه.
/// وهي قائمةٌ قصيرة (وحدات الصنف الواحد)، فالكتابة أسرع من الفتح والمسح.
/// السلوك نفسه في المنتقيات كلها: كتابةٌ تُصفّي، أسهمٌ وEnter وEsc.
///
/// **لا يقبل إلا وحدةً معرَّفة**: الكتابة تصفيةٌ لا إدخالٌ حرّ، فلا تدخل
/// وحدةٌ لا معامل تحويلٍ لها فتُفسد حساب الكمية بوحدة الأساس.
class ImdUnitPicker extends StatelessWidget {
  const ImdUnitPicker({
    super.key,
    required this.units,
    required this.value,
    required this.onChanged,
  });

  /// أسماء الوحدات المتاحة لهذا الصنف.
  final List<String> units;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ImdTypeAhead(
        options: units,
        value: value,
        onChanged: onChanged,
        hint: 'الوحدة…',
        empty: 'لا وحدات لهذا الصنف',
      );
}


/// منتقي الصنف بالكتابة: بحث بالاسم أو الكود مع توحيد الحروف العربية،
/// قائمة منسدلة بحد 60 نتيجة (الاسم + الكود صغيرًا)، أسهم وEnter وEsc.
class ImdItemPicker extends StatefulWidget {
  const ImdItemPicker({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.detailOf,
  });

  final List<Item> items;
  final String value;
  final ValueChanged<String> onChanged;

  /// نص الخيار «الكود — الاسم» (قد يُضاف الرصيد كما في شاشة الصرف).
  final String Function(Item)? labelOf;

  /// سطرُ تفصيلٍ يظهر في الخيار وتلميحه — الرصيد والوحدة مثلًا.
  ///
  /// **الاسم وحده لا يكفي للاختيار**: صنفان متقاربا الاسم يُفرَّق بينهما
  /// برصيدهما أو وحدتهما، ومن يختار الخطأ يكتشفه بعد الحفظ لا قبله.
  final String Function(Item)? detailOf;

  @override
  State<ImdItemPicker> createState() => _ImdItemPickerState();
}


class _ImdItemPickerState extends State<ImdItemPicker> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _listScroll = ScrollController();

  /// الخيار المُبرَز — `ValueNotifier` لا حقلٌ في الحالة عمدًا.
  ///
  /// يتغيّر بمرور الفأرة، و`MouseRegion.onEnter` يُطلق في مرحلة
  /// `postFrameCallbacks` (انظر `RendererBinding._scheduleMouseTrackerUpdate`).
  /// والإطار يريد شجرة العرض نظيفةً في تلك المرحلة: `setState` فيها يُعلّم
  /// عناصر البناء متّسخة، ومنها `LayoutBuilder` — وهذا يستدعي
  /// `scheduleLayoutCallback` بلا فحص المرحلة، فيقع تأكيده. فالإبراز يُعاد
  /// بناؤه وحده عبر `ValueListenableBuilder` بلا لمس الشجرة.
  final _idx = ValueNotifier<int>(-1);
  List<Item> _rows = const [];

  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp('[ً-ْ]'), '')
      .trim();

  String _label(Item i) => widget.labelOf?.call(i) ?? '${i.code} — ${i.name}';

  Item? get _selected =>
      widget.items.where((x) => x.id == widget.value).firstOrNull;

  @override
  void initState() {
    super.initState();
    _sync();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _open(_ctrl.text == (_selected == null ? '' : _label(_selected!))
            ? ''
            : _ctrl.text);
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
    _idx.dispose();
    super.dispose();
  }

  void _sync() {
    final s = _selected;
    imdSetText(_ctrl, s == null ? '' : _label(s));
  }

  /// نصٌّ يُبحث فيه: الكود والاسم والتسمية المخصّصة معًا — فمن يحفظ الكود
  /// يكتبه، ومن يحفظ الاسم يكتبه، ولا يُطالَب أحدهما بصيغة الآخر.
  String _haystack(Item i) => '${i.code} ${i.name} ${_label(i)}';

  void _open(String q) {
    // حارسٌ ضد نداءٍ متأخّر يصل بعد تخلّص الودجة من حالتها — مؤقّت مغلق
    // التركيز (150ms أدناه) قد يستدعي هذا المسار بعد أن يستبدل الشاشةُ الأمّ
    // الصفّ كلّه (كإعادة تحميل نموذجٍ أو استعادة مسودة) فتتخلّص من هذه الحالة.
    if (!mounted) return;
    final nq = norm(q);
    _rows = (nq.isEmpty
            ? widget.items
            : widget.items.where((i) => norm(_haystack(i)).contains(nq)))
        .take(60)
        .toList();
    _idx.value = -1;
    if (!_portal.isShowing) _portal.show();
    setState(() {});
  }

  void _close() {
    if (!mounted) return;
    if (_portal.isShowing) _portal.hide();
    _idx.value = -1;
    setState(() {});
  }

  void _pick(Item i) {
    if (!mounted) return;
    ImdPageDirty.mark(context);
    widget.onChanged(i.id);
    imdSetText(_ctrl, _label(i));
    _close();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown ||
        e.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (!_portal.isShowing) _open(_ctrl.text);
      _idx.value = (_idx.value + (e.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1))
          .clamp(0, _rows.isEmpty ? 0 : _rows.length - 1);
      if (_listScroll.hasClients) {
        _listScroll.jumpTo(
            (_idx.value * 38.0).clamp(0, _listScroll.position.maxScrollExtent));
      }
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter &&
        _portal.isShowing &&
        _rows.isNotEmpty) {
      _pick(_rows[_idx.value >= 0 ? _idx.value : 0]);
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
          // عرض الحقل من `LayerLink` لا من `findRenderObject().size`: الثاني
          // يقرأ التخطيط أثناء البناء، وهو ما يمنعه الإطار خارج نطاقه.
          final targetWidth = _link.leaderSize?.width ?? 300;
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
                  width: targetWidth,
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: imdShadowOverlay(c),
                  ),
                  child: _rows.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text('لا توجد أصناف مطابقة',
                              style: TextStyle(fontSize: 13, color: c.muted)),
                        )
                      : ListView.builder(
                          controller: _listScroll,
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _rows.length,
                          itemBuilder: (ctx, i) {
                            final it = _rows[i];
                            final detail = widget.detailOf?.call(it) ?? '';
                            final row = MouseRegion(
                              cursor: ImdCursor.click,
                              // لا `setState` هنا: هذا النداء يقع في مرحلة
                              // `postFrameCallbacks`، فيُبنى الإبراز وحده.
                              onEnter: (_) => _idx.value = i,
                              child: GestureDetector(
                                onTapDown: (_) => _pick(it),
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _idx,
                                  builder: (context, idx, child) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: i == idx ? c.accentSoft : null,
                                      border: i == _rows.length - 1
                                          ? null
                                          : Border(
                                              bottom: BorderSide(color: c.line)),
                                    ),
                                    child: child,
                                  ),
                                  child: Row(children: [
                                    // **الكود شارةٌ لا نصٌّ ملتصق بالاسم**:
                                    // العين تمسحه في عمودٍ واحد، والاسم يبقى
                                    // أوّل ما يُقرأ.
                                    Container(
                                      margin: const EdgeInsetsDirectional.only(
                                          end: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: c.subtle,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text(it.code,
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: c.muted)),
                                    ),
                                    Expanded(
                                      child: Text(it.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13, color: c.text)),
                                    ),
                                    if (detail.isNotEmpty)
                                      Text(detail,
                                          style: TextStyle(
                                              fontSize: 10.5, color: c.muted)),
                                  ]),
                                ),
                              ),
                            );
                            return detail.isEmpty
                                ? row
                                : Semantics(
                                    label: '${it.code} — ${it.name}'
                                        '\n$detail',
                                    child: row,
                                  );
                          },
                        ),
                ),
              ),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: ImdCompact.of(context)
                  ? ImdSizes.compactField
                  : ImdSizes.touchMin),
          child: Focus(
            onKeyEvent: _key,
            canRequestFocus: false,
            skipTraversal: true,
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onChanged: _open,
              style: TextStyle(
                  fontSize: ImdCompact.of(context) ? 13 : 14, color: c.text),
              decoration:
                  imdFieldDecoration(context, hint: 'اكتب اسم الصنف أو الكود…'),
            ),
          ),
        ),
      ),
    );
  }
}
