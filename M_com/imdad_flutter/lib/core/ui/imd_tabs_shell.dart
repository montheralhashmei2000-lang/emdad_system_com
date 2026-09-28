import 'package:flutter/material.dart';

import '../security/perm.dart';
import 'imd_empty_state.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';
import '../../domain/access_control.dart';

/// تبويبةٌ في غلافٍ يجمع شاشاتٍ متقاربة.
class ImdShellTab {
  const ImdShellTab({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.perm,
  });

  final String id;
  final String label;
  final String icon;
  final WidgetBuilder builder;

  /// صلاحية هذه التبويبة وحدها — تُخفى إن لم يملكها المستخدم.
  ///
  /// الجمعُ في شاشةٍ واحدة تنظيمٌ للقائمة لا توسيعٌ للأذونات: من يملك
  /// المستودعات ولا يملك المركبات يرى المستودعات فقط، كما كان قبل الجمع.
  final String? perm;
}

/// غلافٌ يجمع شاشاتِ قسمٍ فرعيّ في بندٍ واحد بالقائمة.
///
/// **الشريط الجانبي فهرسٌ لا سجل.** عشرون شاشةً في قائمةٍ واحدة تُقرأ بالبحث
/// لا بالنظر؛ وجمعُ المتقارب منها — حركةٌ، وبياناتٌ أساسية، وتقارير — يُعيد
/// للقائمة معناها.
///
/// والشاشات تبقى كما هي: يُعلَّق فوقها شريط تبويبات ويُترك لها تمريرُها
/// الخاص، فلا تمريرٌ داخل تمرير ولا عنوانٌ يُكرَّر.
class ImdTabsShell extends StatefulWidget {
  const ImdTabsShell({
    super.key,
    required this.tabs,
    this.initial = '',
    this.emptyMessage = 'لا صلاحية لأي شاشة في هذا القسم',
  });

  final List<ImdShellTab> tabs;
  final String initial;
  final String emptyMessage;

  @override
  State<ImdTabsShell> createState() => _ImdTabsShellState();
}

class _ImdTabsShellState extends State<ImdTabsShell> {
  String _tab = '';

  @override
  void didUpdateWidget(covariant ImdTabsShell old) {
    super.didUpdateWidget(old);
    // التنقّل من اختصارٍ في اللوحة يفتح الغلاف نفسه على تبويبةٍ أخرى.
    if (old.initial != widget.initial && widget.initial.isNotEmpty) {
      setState(() => _tab = widget.initial);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    final visible = [
      for (final t in widget.tabs)
        if (t.perm == null || perm.has(t.perm!, PermAction.view)) t,
    ];
    if (visible.isEmpty) {
      return ImdPage(children: [ImdEmptyState.noPermission(message: widget.emptyMessage)]);
    }

    final wanted = _tab.isEmpty ? widget.initial : _tab;
    final current = visible.any((t) => t.id == wanted) ? wanted : visible.first.id;
    final tab = visible.firstWhere((t) => t.id == current);
    final c = context.imd;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          child: ImdPillTabs<String>(
            value: current,
            onChanged: (v) => setState(() => _tab = v),
            tabs: [
              for (final t in visible) ImdTab(t.id, t.label, icon: t.icon),
            ],
          ),
        ),
        // الشاشة المختارة تحتفظ بتمريرها ولوحاتها كما لو فُتحت وحدها.
        Expanded(child: KeyedSubtree(key: ValueKey(tab.id), child: tab.builder(context))),
      ],
    );
  }
}
