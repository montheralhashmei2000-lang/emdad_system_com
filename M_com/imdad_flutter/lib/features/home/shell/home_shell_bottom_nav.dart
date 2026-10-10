part of '../home_shell.dart';

/// شريطٌ سفليّ لأشهر أبواب القسم — وما وراءها في الدرج.
///
/// **الإبهام لا يبلغ أعلى الشاشة.** الدرج وحده يكلّف نقرتين لكل تنقّل، وأمينُ
/// المستودع ينتقل بين الصرف والاستلام عشرات المرات في الساعة.
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.space,
    required this.page,
    required this.hasPerm,
    required this.onGo,
    required this.onMore,
  });

  final String space;
  final String page;
  final bool Function(String) hasPerm;
  final ValueChanged<String> onGo;
  final VoidCallback onMore;

  /// أبوابٌ ثلاثة بعد الرئيسية — والرابع «المزيد» يفتح القائمة كاملة.
  // أُشير بها إلى معرّفات أبوابٍ حذفناها من الشجرة عند تفكيكها إلى بنودٍ
  // مباشرة؛ استُبدلت ببنودٍ فرديةٍ ما زالت في `_menu` تمثّل نفس الغرض
  // (أشهر ما يُفتح) بدل أن تختفي صفوف المفضّلة في الشريط السفليّ صامتة.
  static const Map<String, List<String>> _main = {
    AppSpace.supply: ['issue', 'receive', 'balances'],
    AppSpace.fuel: ['fuelIssue', 'fuelAllocations', 'fuelDaily'],
  };

  static _MenuItem? _itemOf(String id) {
    for (final sec in _menu) {
      for (final i in sec.items) {
        if (i.id == id) return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final ids = [
      for (final id in _main[space] ?? const <String>[])
        if (hasPerm(id)) id,
    ];
    final items = [
      for (final id in ids)
        if (_itemOf(id) != null) _itemOf(id)!,
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.side,
        border: Border(top: BorderSide(color: c.sideLine)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(children: [
            _BottomTile(
              icon: 'home',
              label: 'الرئيسية',
              on: page == 'dash',
              onTap: () => onGo('dash'),
            ),
            for (final i in items)
              _BottomTile(
                icon: i.icon,
                label: i.name,
                on: page == i.id,
                onTap: () => onGo(i.id),
              ),
            _BottomTile(
              icon: 'menu',
              label: 'المزيد',
              on: false,
              onTap: onMore,
            ),
          ]),
        ),
      ),
    );
  }
}

class _BottomTile extends StatelessWidget {
  const _BottomTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final fg = on ? c.accent : c.sideMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ImdIcon(icon, size: 19, color: fg),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
