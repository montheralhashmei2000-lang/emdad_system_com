part of '../home_shell.dart';

/// الشريط العلوي: عنوان الشاشة، وتبديل القسم، وتبديل السمة، وحالة
/// المزامنة، وحساب المستخدم.
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

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    // **الشريط العلويّ نظيفٌ على الجهازين.** ما يُزاح أولًا شاراتُ الحالة،
    // ثم اسم المستخدم، ثم اسم النظام — وتبقى الصورة والجرس والقائمة، وهي
    // ما يُنقر. وبلا هذا التدرّج يفيض الصف ويُرسم شريطًا أصفر.
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final showIam = w > 720;
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
            // تبديل القسم: أيقونةٌ دائمًا، واسمه معها ما اتّسع الشريط. من
            // يملك مساحةً واحدة يبقى الاسم معروضًا له لكن بلا تفاعل — لا
            // تبديل إلى لا شيء.
            MouseRegion(
              cursor: canSwitch ? ImdCursor.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: canSwitch ? onSwitchSpace : null,
                behavior: HitTestBehavior.opaque,
                child: Semantics(
                  label: canSwitch ? 'تبديل القسم' : AppSpace.label(space),
                  child: Container(
                    height: 36,
                    padding: EdgeInsetsDirectional.fromSTEB(
                        10, 6, showTitle ? 12 : 10, 6),
                    decoration: BoxDecoration(
                      color: c.subtle,
                      border: Border.all(color: c.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      ImdIcon(
                          canSwitch
                              ? 'swap'
                              : (AppSpace.icons[space] ?? 'package'),
                          size: 13,
                          color: c.muted),
                      if (showTitle) ...[
                        const SizedBox(width: 6),
                        Text(AppSpace.label(space),
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.text2)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
            const Spacer(),
            ImdIconButton(
              icon: c.isDark ? 'sun' : 'moon',
              tooltip: c.isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
              onPressed: () => _toggleTheme(context),
            ),
            const SizedBox(width: 8),
            NotificationBell(onOpenPage: onOpenPage, space: space),
            const SizedBox(width: 8),
            Container(
              height: 40,
              padding: EdgeInsetsDirectional.fromSTEB(6, 4, showName ? 10 : 6, 4),
              decoration: BoxDecoration(
                  color: c.subtle, borderRadius: BorderRadius.circular(99)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(name: userName, size: 32, fontSize: 14),
                  if (showName) ...[
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.text)),
                    ),
                  ],
                  if (showIam) ...[
                    const SizedBox(width: 10),
                    const _StatusPill(label: 'IAM محمي'),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// كبسولة حالةٍ بنقطةٍ ملوّنة (شارة «IAM محمي» في الشريط العلوي). حالة
/// المزامنة انتقلت إلى [ImdStatusBar].
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final (_, foreground) = ImdChip.colors(c, ImdTone.ok);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.text2,
                height: 1.6)),
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
