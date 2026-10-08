part of '../home_shell.dart';

/// يبدّل السمة صراحةً بين فاتحٍ وداكن (لا «تلقائي»): زرٌّ سريعٌ يفترض
/// نيّة المستخدم من السطوع الحالي الفعلي — ويحفظها فتبقى بعد إعادة
/// التشغيل، بنفس مسار حفظ السمة من شاشة الهوية.
Future<void> _toggleTheme(BuildContext context) async {
  final next = Theme.of(context).brightness == Brightness.dark ? 'light' : 'dark';
  final settings = SettingsRepo(context.read<AppDatabase>());
  final id = await settings.identity();
  await settings.saveIdentity(id.copyWith(themePref: next));
  if (context.mounted) context.read<ImdTheme>().apply(next);
}

/// الشريط العلوي **للجوال**: زرّ القائمة، واسم النظام، وتبديل القسم والسمة
/// والجرس والحساب. سطح المكتب يستعمل [_DesktopBar] (شريطٌ واحدٌ يجمع التبويبات).
///
/// تبديل القسم انتقل إليه من الشريط الجانبي: هو إجراءٌ نادر (مرةً في بداية
/// الجلسة غالبًا) لا يستحقّ ارتفاعًا دائمًا في القائمة، وهنا يبقى في متناول
/// اليد بلا أن يزاحم أبوابها.
class _Topbar extends StatelessWidget {
  const _Topbar({
    required this.userName,
    required this.showBurger,
    required this.onBurger,
    required this.onOpenPage,
    required this.space,
    required this.canSwitch,
    required this.onSwitchSpace,
  });

  final String userName;
  final bool showBurger;
  final VoidCallback onBurger;
  final ValueChanged<String> onOpenPage;

  /// القسم الذي يقف فيه المستخدم — الجرس يخصّ ما بين يديه.
  final String space;

  /// زر التبديل لا يظهر تفاعليًّا لمن يملك مساحةً واحدة: تبديلٌ إلى لا شيء،
  /// لكن اسم القسم يبقى معروضًا فيعرف من فتحه أين هو.
  final bool canSwitch;
  final VoidCallback onSwitchSpace;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // **الشريط العلويّ نظيفٌ على الجهازين.** ما يُزاح أولًا اسم المستخدم، ثم
    // اسم النظام — وتبقى الصورة والجرس والقائمة، وهي ما يُنقر. وبلا هذا
    // التدرّج يفيض الصف ويُرسم شريطًا أصفر.
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final showName = w > 560;
      final showTitle = w > 430;
      // أندرويد ١٥+ يرسم التطبيق خلف شريط الحالة: بلا هذا الإزاحة يطلع الشريط
      // العلوي (الاسم والمزامنة) تحت الساعة والبطارية. على ويندوز الإزاحة صفر.
      final inset = MediaQuery.paddingOf(context).top;
      return Container(
        height: ImdSizes.topbarHeight + inset,
        padding: EdgeInsets.fromLTRB(12, 8 + inset, 12, 10),
        decoration: BoxDecoration(
          color: c.topbar(mica: ImdWindow.micaActive.value),
          border: Border(bottom: BorderSide(color: c.line)),
        ),
        child: Row(
          children: [
            if (showBurger) ...[
              ImdIconButton(icon: 'menu', onPressed: onBurger),
              const SizedBox(width: 8),
            ],
            if (showTitle)
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'نظام '),
                    TextSpan(
                        text: 'الإمداد والتموين',
                        style: TextStyle(
                            color: c.accent, fontWeight: FontWeight.w700)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.text2),
                ),
              ),
            if (showTitle) ...[
              const SizedBox(width: 10),
              const ImdMenuBar(),
            ],
            const SizedBox(width: 10),
            _SpacePill(space: space, canSwitch: canSwitch, onTap: onSwitchSpace, showLabel: showTitle),
            const Spacer(),
            const _SearchButton(),
            const SizedBox(width: 8),
            _ThemeButton(isDark: c.isDark),
            const SizedBox(width: 8),
            NotificationBell(onOpenPage: onOpenPage, space: space),
            const SizedBox(width: 8),
            _UserChip(userName: userName, showName: showName, height: 40, avatar: 32),
          ],
        ),
      );
    });
  }
}

/// **الشريط الواحد لسطح المكتب**: زرّ طيّ القائمة، فالتبويبات، فالأدوات، فأزرار
/// النافذة — كلها في صفٍّ واحد بدل ثلاثة (شريط عنوان النظام + شريط علوي + شريط
/// تبويبات). حين يُنزع إطار ويندوز يصير هذا الصفُّ شريطَ
/// العنوان نفسه: يُسحب منه فراغُه لتحريك النافذة، ويُنقر مرتين لتكبيرها.
class _DesktopBar extends StatelessWidget {
  const _DesktopBar({
    required this.userName,
    required this.collapsed,
    required this.onToggleSide,
    required this.pages,
    required this.activeId,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.onOpenPage,
    required this.space,
    required this.canSwitch,
    required this.onSwitchSpace,
  });

  final String userName;

  /// القائمة الجانبية مطويّةٌ الآن؟ (تحدّد تلميح الزرّ.)
  final bool collapsed;
  final VoidCallback onToggleSide;
  final List<ImdOpenPage> pages;
  final String activeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final ValueChanged<String> onCloseOthers;
  final ValueChanged<String> onOpenPage;
  final String space;
  final bool canSwitch;
  final VoidCallback onSwitchSpace;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    const h = ImdSizes.desktopBarHeight;
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      // التبويبات أولى بالعرض من الأدوات: تُسقَط القوائم أولًا ثم اسم المستخدم
      // ثم اسم القسم — وتبقى الأيقونات (السمة، الجرس، الصورة).
      final showMenus = w > 1180;
      final showName = w > 1040;
      final showLabel = w > 1040;
      return Container(
          height: h,
          decoration: BoxDecoration(
            color: c.topbar(mica: ImdWindow.micaActive.value),
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: Row(children: [
            const SizedBox(width: 8),
            Tooltip(
              message: collapsed ? 'توسيع القائمة' : 'طيّ القائمة',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onToggleSide,
                child: SizedBox(
                  width: 34,
                  height: 28,
                  child: Center(child: ImdIcon('menu', size: 16, color: c.text2)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ImdPageTabs(
                  embedded: true,
                  // الرئيسية تُفتح من الشريط الجانبي ولا تحتاج تبويبة.
                  pages: [for (final p in pages) if (p.id != 'dash') p],
                  activeId: activeId,
                  onSelect: onSelect,
                  onClose: onClose,
                  onCloseOthers: onCloseOthers,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (showMenus) ...[const ImdMenuBar(), const SizedBox(width: 8)],
            _SpacePill(space: space, canSwitch: canSwitch, onTap: onSwitchSpace, showLabel: showLabel, dense: true),
            const SizedBox(width: 8),
            const _SearchButton(dense: true),
            const SizedBox(width: 6),
            _ThemeButton(isDark: c.isDark, dense: true),
            const SizedBox(width: 6),
            NotificationBell(onOpenPage: onOpenPage, space: space, dense: true),
            const SizedBox(width: 8),
            _UserChip(userName: userName, showName: showName, height: 30, avatar: 24),
            const SizedBox(width: 10),
          ]),
      );
    });
  }
}

/// تبديل القسم: أيقونةٌ دائمًا، واسمه معها ما اتّسع الشريط. من يملك مساحةً
/// واحدة يبقى الاسم معروضًا له لكن بلا تفاعل — لا تبديل إلى لا شيء.
class _SpacePill extends StatelessWidget {
  const _SpacePill({required this.space, required this.canSwitch, required this.onTap, required this.showLabel, this.dense = false});

  final bool dense;
  final String space;
  final bool canSwitch;
  final VoidCallback onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return MouseRegion(
      cursor: canSwitch ? ImdCursor.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: canSwitch ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          label: canSwitch ? 'تبديل القسم' : AppSpace.label(space),
          child: Container(
            height: dense ? 28 : 34,
            padding: EdgeInsetsDirectional.fromSTEB(10, dense ? 3 : 6, showLabel ? 12 : 10, dense ? 3 : 6),
            decoration: BoxDecoration(
              color: c.subtle,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ImdIcon(canSwitch ? 'swap' : (AppSpace.icons[space] ?? 'package'), size: 13, color: c.muted),
              if (showLabel) ...[
                const SizedBox(width: 6),
                Text(AppSpace.label(space),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text2)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// البحث العام: الزرُّ نظيرُ Ctrl+K لمن لا يحفظ الاختصار أو لا لوحة مفاتيح
/// لديه. الإجراء نفسه المسجَّل في [ImdScreenActions.onSearch] (يسجّله الإطار)،
/// فلا يعرف الشريط شيئًا عن اللوحة ولا عن الصفحات.
class _SearchButton extends StatelessWidget {
  const _SearchButton({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) => Tooltip(
        // `ImdIconButton` لا تمرّر `tooltip` إلى زرّها، فالتلميح بالغلاف كما
        // يفعل زرّ طيّ القائمة في هذا الشريط نفسه.
        message: ImdShortcuts.supported ? 'البحث العام (Ctrl+K)' : 'البحث العام',
        child: ImdIconButton(
          icon: 'search',
          dense: dense,
          onPressed: () => ImdScreenActions.maybeOf(context)?.onSearch?.call(),
        ),
      );
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({required this.isDark, this.dense = false});
  final bool isDark;
  final bool dense;

  @override
  Widget build(BuildContext context) => ImdIconButton(
        icon: isDark ? 'sun' : 'moon',
        tooltip: isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
        dense: dense,
        onPressed: () => _toggleTheme(context),
      );
}

/// صورة المستخدم واسمه. (شارة «IAM محمي» أُزيلت من الشريط.)
class _UserChip extends StatelessWidget {
  const _UserChip({required this.userName, required this.showName, required this.height, required this.avatar});

  final String userName;
  final bool showName;
  final double height;
  final double avatar;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      height: height,
      padding: EdgeInsetsDirectional.fromSTEB(4, 4, showName ? 12 : 4, 4),
      decoration: BoxDecoration(color: c.subtle, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Avatar(name: userName, size: avatar, fontSize: 13),
        if (showName) ...[
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
          ),
        ],
      ]),
    );
  }
}

/// دائرة الحرف الأول من اسم المستخدم.
class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.name, required this.size, required this.fontSize});
  final String name;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '؟' : name.characters.first.toUpperCase(),
        style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: c.onAccent),
      ),
    );
  }
}
