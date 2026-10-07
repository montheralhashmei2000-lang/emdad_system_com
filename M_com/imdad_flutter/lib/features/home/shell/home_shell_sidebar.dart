part of '../home_shell.dart';

/// القائمة الجانبية الداكنة.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.space,
    required this.openSec,
    required this.hasPerm,
    required this.userName,
    required this.onGo,
    required this.onToggle,
    required this.onLogout,
    this.rail = false,
    this.width = ImdSizes.sideWidth,
  });

  /// عرض القائمة الكاملة — يسحبه المستخدم بفاصلٍ قابلٍ للسحب.
  final double width;

  /// أيقوناتٌ بلا أسماء — لشاشةٍ لا تتسع لـ٢٩٠ بكسل من قائمة.
  final bool rail;

  /// بنود المساحة التي يملكها المستخدم، مسطَّحةً — وهي ما يُرسم في القضيب.
  List<_MenuItem> _items() => [
        for (final sec in _menu)
          for (final i in sec.items)
            if (AppSpace.shows(i.space, space) && hasPerm(i.id)) i,
      ];

  /// أبواب القسم [sec] التي يراها المستخدم في المساحة الحالية.
  List<_MenuItem> _itemsOf(_MenuSection sec) =>
      [for (final i in sec.items) if (AppSpace.shows(i.space, space) && hasPerm(i.id)) i];

  /// هل للمساحة قسمٌ واحد فيُعرض مسطّحًا بلا رأس؟
  static bool _flat(String space, bool Function(String) hasPerm) =>
      _menu
          .where((s) => s.items
              .any((i) => AppSpace.shows(i.space, space) && hasPerm(i.id)))
          .length <=
      1;

  final String page;

  /// مساحة العمل الحالية — تُرشَّح بها بنود القائمة.
  final String space;

  final String? openSec;
  final bool Function(String page) hasPerm;
  final String userName;
  final ValueChanged<String> onGo;
  final ValueChanged<String> onToggle;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    if (rail) return _rail(context);
    final c = context.imd;
    return Container(
      width: width,
      decoration: BoxDecoration(
        // تدرّج خفيف من لون الشريط إلى أغمق منه أسفلًا.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.side.withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
            c.sideDeep
                .withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
          ],
        ),
        border: BorderDirectional(start: BorderSide(color: c.sideLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      // الرأس والتذييل ثابتان، والقائمة بينهما تتمرّر. لا `IntrinsicHeight` هنا:
      // `AnimatedSize` تُرجع ارتفاع الطفل الهدف لا المتحرّك، فيفيض العمود
      // مؤقتًا عند طيّ قسمٍ أو التبديل بين قسمين.
      child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  // الرئيسية بندٌ مستقلٌّ دائمًا في القسمين — لا قائمة فرعية
                  // تحته؛ وجهتها تتبع القسم النشط (`dash` أو `fuelDashboard`).
                  _SideTile(
                    icon: 'home',
                    label: 'الرئيسية',
                    kind: _SideKind.home,
                    on: page == (space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
                    onTap: () =>
                        onGo(space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
                  ),
                  // قسمٌ بقائمةٍ واحدة يُعرض مسطّحًا: رأسُ قسمٍ يُطوى على كل
                  // ما في الشاشة ليس تصنيفًا، بل نقرةٌ تُدفع قبل كل شيء.
                  if (_flat(space, hasPerm))
                    for (final i in _menu.expand((x) => x.items).where(
                        (i) => AppSpace.shows(i.space, space) && hasPerm(i.id)))
                      _SideTile(
                        icon: i.icon,
                        label: i.name,
                        kind: _SideKind.item,
                        on: page == i.id,
                        onTap: () => onGo(i.id),
                      )
                  else
                    for (final s in _menu)
                      if (s.items.any((i) =>
                          AppSpace.shows(i.space, space) && hasPerm(i.id))) ...[
                        _SideTile(
                          icon: s.icon,
                          label: s.name,
                          kind: _SideKind.header,
                          open: openSec == s.sec,
                          onTap: () => onToggle(s.sec),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.ease,
                          alignment: Alignment.topCenter,
                          child: openSec == s.sec
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final i in s.items.where((i) =>
                                        AppSpace.shows(i.space, space) &&
                                        hasPerm(i.id)))
                                      _SideTile(
                                        icon: i.icon,
                                        label: i.name,
                                        kind: _SideKind.item,
                                        on: page == i.id,
                                        onTap: () => onGo(i.id),
                                      ),
                                  ],
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.only(top: 14),
                    decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.sideLine))),
                    // بلا بطاقة مستخدمٍ هنا: الاسم والصلاحية معروضان في
                    // الشريط العلوي، وهذا الشريط لا يحمل غير الخروج فيقصر
                    // ارتفاعه لصالح القائمة.
                    child: _SideTile(
                        icon: 'lock',
                        label: 'تسجيل خروج',
                        kind: _SideKind.logout,
                        onTap: onLogout),
                  ),
                ],
      ),
    );
  }
  /// شريطٌ ضيّق: أيقونةٌ لكل باب واسمُه في تلميحها.
  ///
  /// **الأيقونة تكفي لمن يعرف طريقه.** من يفتح الشاشة كل يوم لا يقرأ اسم
  /// البند، بل يقصد موضعه؛ والاسم يبقى في التلميح لمن يبحث.
  Widget _rail(BuildContext context) {
    final c = context.imd;
    final items = _items();
    return Container(
      width: 68,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.side.withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
            c.sideDeep
                .withValues(alpha: ImdWindow.micaActive.value ? .82 : 1),
          ],
        ),
        border: BorderDirectional(start: BorderSide(color: c.sideLine)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        _RailTile(
          icon: 'home',
          label: 'الرئيسية',
          on: page == (space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
          onTap: () => onGo(space == AppSpace.fuel ? 'fuelDashboard' : 'dash'),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(children: [
              // قسمٌ بقائمةٍ واحدة يُعرض مسطّحًا؛ وما سواه تظهر **أيقونات الأقسام
              // الرئيسية فقط** — ونقرةٌ على أيقونة قسمٍ تفتح قائمةً بأبوابه بجوارها.
              if (_flat(space, hasPerm))
                for (final i in items)
                  _RailTile(
                    icon: i.icon,
                    label: i.name,
                    on: page == i.id,
                    onTap: () => onGo(i.id),
                  )
              else
                for (final sec in _menu)
                  if (_itemsOf(sec).isNotEmpty)
                    _RailSection(
                      icon: sec.icon,
                      label: sec.name,
                      on: _itemsOf(sec).any((i) => i.id == page),
                      items: _itemsOf(sec),
                      page: page,
                      onGo: onGo,
                    ),
            ]),
          ),
        ),
        _RailTile(
          icon: 'log-out',
          label: 'تسجيل الخروج',
          on: false,
          danger: true,
          onTap: onLogout,
        ),
        const SizedBox(height: 10),
      ]),
    );
  }
}

/// أيقونةُ بابٍ في الشريط الضيّق، واسمُه في تلميحها.
class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.danger = false,
  });

  final String icon;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final fg = danger ? c.danger : (on ? c.sideText : c.sideMuted);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 48,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.sideActive : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ImdIcon(icon, size: 19, color: fg),
          ),
        ),
      ),
    );
  }
}

/// أيقونة قسمٍ رئيسيّ في الشريط المطويّ: تلميحها اسمه، ونقرتها تفتح قائمةً بأبوابه.
///
/// القائمة تُفتح عند الحافة الخارجية للأيقونة (يسارها في الواجهة العربية) فلا
/// تغطّي الشريط نفسه، والبابُ المفتوح حاليًّا يُعلَّم فيها.
class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.icon,
    required this.label,
    required this.on,
    required this.items,
    required this.page,
    required this.onGo,
  });

  final String icon;
  final String label;

  /// الصفحة الحالية داخل هذا القسم.
  final bool on;
  final List<_MenuItem> items;
  final String page;
  final ValueChanged<String> onGo;

  void _open(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    showImdContextMenu(context, Offset(origin.dx, origin.dy), [
      for (final i in items)
        ImdMenuItem(
          label: i.id == page ? '${i.name}  ●' : i.name,
          icon: i.icon,
          onTap: () => onGo(i.id),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final fg = on ? c.sideText : c.sideMuted;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: true,
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 48,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? c.sideActive : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ImdIcon(icon, size: 19, color: fg),
          ),
        ),
      ),
    );
  }
}

enum _SideKind { home, header, item, logout }

class _SideTile extends StatefulWidget {
  const _SideTile({
    required this.icon,
    required this.label,
    required this.kind,
    required this.onTap,
    this.on = false,
    this.open = false,
  });

  final String icon;
  final String label;
  final _SideKind kind;
  final VoidCallback onTap;
  final bool on;
  final bool open;

  @override
  State<_SideTile> createState() => _SideTileState();
}

class _SideTileState extends State<_SideTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    late final Color bg;
    late final Color fg;
    Border? border;
    late final EdgeInsets pad;
    late final EdgeInsets margin;
    late final double fs;
    late final FontWeight fw;
    late final double radius;
    Color? iconColor;
    switch (widget.kind) {
      case _SideKind.home:
        bg = _hover ? c.sideHover : c.side2;
        fg = c.sideBright;
        border = Border.all(color: c.sideBorder);
        pad = const EdgeInsets.symmetric(horizontal: 16, vertical: 13);
        margin = const EdgeInsets.only(bottom: 10);
        fs = 14;
        fw = FontWeight.w600;
        radius = 10;
      case _SideKind.header:
        bg = _hover ? c.sideHover : Colors.transparent;
        fg = (_hover || widget.open) ? c.sideBright : c.sideMuted;
        pad = const EdgeInsets.symmetric(horizontal: 14, vertical: 11);
        margin = const EdgeInsets.only(top: 6, bottom: 4);
        fs = 12.5;
        fw = FontWeight.w600;
        radius = 8;
      case _SideKind.item:
        bg = widget.on
            ? c.sideActive
            : (_hover ? c.sideHover : Colors.transparent);
        fg = (widget.on || _hover)
            ? c.sideBright
            : c.sideText.withValues(alpha: .86);
        iconColor = widget.on ? ImdColors.dark.accentHover : null;
        pad = const EdgeInsets.only(left: 10, top: 11, right: 14, bottom: 11);
        margin = const EdgeInsets.only(left: 4, top: 1, bottom: 1);
        fs = 13.5;
        fw = FontWeight.w500;
        radius = 8;
      case _SideKind.logout:
        bg = _hover ? c.sideHover : Colors.transparent;
        fg = c.sideText;
        border = Border.all(color: _hover ? c.sideMuted : c.sideBorder);
        pad = const EdgeInsets.all(13);
        margin = EdgeInsets.zero;
        fs = 14;
        fw = FontWeight.w600;
        radius = 10;
    }
    final isItem = widget.kind == _SideKind.item;
    return MouseRegion(
      cursor: ImdCursor.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: margin,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: isItem ? null : border,
          ),
          foregroundDecoration: isItem && widget.on
              ? BoxDecoration(
                  border: Border(
                      right: BorderSide(color: ImdColors.dark.accentHover, width: 2)),
                )
              : null,
          padding: pad,
          child: Row(
            mainAxisAlignment: widget.kind == _SideKind.logout
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              ImdIcon(widget.icon, size: fs * 1.1, color: iconColor ?? fg),
              SizedBox(
                  width: widget.kind == _SideKind.header
                      ? 8
                      : (widget.kind == _SideKind.logout ? 6 : 10)),
              if (widget.kind == _SideKind.logout)
                Text(widget.label,
                    style: TextStyle(
                        fontSize: fs, fontWeight: fw, color: fg, height: 1.6))
              else
                Expanded(
                  child: Text(widget.label,
                      style: TextStyle(
                          fontSize: fs, fontWeight: fw, color: fg, height: 1.6),
                      overflow: TextOverflow.ellipsis),
                ),
              if (widget.kind == _SideKind.header) ...[
                ImdIcon(widget.open ? 'chevron-down' : 'chevron-left',
                    size: 12, color: c.sideMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// فاصلٌ رأسيّ رفيع بين القائمة الجانبية والمحتوى يُسحب لتغيير عرضها —
/// مؤشّر تغيير الحجم وخطٌّ بلون العلامة عند المرور، كنوافذ سطح المكتب.
class _SideSplitter extends StatefulWidget {
  const _SideSplitter({required this.onDrag, required this.onEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  State<_SideSplitter> createState() => _SideSplitterState();
}

class _SideSplitterState extends State<_SideSplitter> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final on = _hover || _drag;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _drag = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _drag = false);
          widget.onEnd();
        },
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: on ? 3 : 1,
              color: on ? c.accent : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
