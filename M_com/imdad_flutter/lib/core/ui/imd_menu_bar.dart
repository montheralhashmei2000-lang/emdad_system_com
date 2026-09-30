import 'package:flutter/material.dart';

import 'imd_screen_actions.dart';
import 'imd_tokens.dart';
import 'imd_widgets.dart';

/// بندا «ملف»/«مساعدة» — يُدمجان داخل الشريط العلوي بجانب اسم النظام مباشرة،
/// على وندوز/لينكس/ماك وحدها ([ImdShortcuts.supported])؛ يغيبان تمامًا عن
/// الجوال بلا أي أثر على تخطيط الشريط هناك.
///
/// بنود «ملف» تعكس ما سجّلته الشاشة النشطة فعلًا في [ImdScreenActions]
/// فتُعطَّل تلقائيًا حين لا تدعمها الشاشة الحالية — لا قائمة جامدة تدّعي
/// إجراءً لا تملكه الشاشة.
class ImdMenuBar extends StatelessWidget {
  const ImdMenuBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ImdShortcuts.supported) return const SizedBox.shrink();
    final actions = ImdScreenActions.maybeOf(context);
    if (actions == null) return const SizedBox.shrink();
    final c = context.imd;

    PopupMenuItem<String> item(String label, String shortcut, bool enabled, String value) {
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Text(shortcut, style: TextStyle(fontSize: 11, color: c.muted)),
        ]),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      ImdMenuButton<String>(
        label: 'ملف',
        icon: 'file',
        small: true,
        items: (_) => [
          item('سند جديد', 'Ctrl+N', actions.onNewDoc != null, 'new'),
          item('حفظ', 'Ctrl+S', actions.onSave != null, 'save'),
          item('طباعة', 'Ctrl+P', actions.onPrint != null, 'print'),
          item('تحديث', 'F5', actions.onRefresh != null, 'refresh'),
        ],
        onSelected: (v) {
          switch (v) {
            case 'new':
              actions.onNewDoc?.call();
            case 'save':
              actions.onSave?.call();
            case 'print':
              actions.onPrint?.call();
            case 'refresh':
              actions.onRefresh?.call();
          }
        },
      ),
      const SizedBox(width: 6),
      ImdMenuButton<String>(
        label: 'مساعدة',
        icon: 'info',
        small: true,
        items: (_) => const [
          PopupMenuItem<String>(value: 'shortcuts', child: Text('اختصارات لوحة المفاتيح')),
        ],
        onSelected: (v) {
          if (v == 'shortcuts') _showShortcuts(context);
        },
      ),
    ]);
  }

  void _showShortcuts(BuildContext context) {
    showImdModal<void>(
      context,
      title: 'اختصارات لوحة المفاتيح',
      icon: 'info',
      maxWidth: 420,
      builder: (ctx) {
        final c = ctx.imd;
        Widget row(String key, String desc) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 84,
                  child: Text(key, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c.text)),
                ),
                Expanded(
                  child: Text(desc, style: TextStyle(fontSize: 13, color: c.text2, height: 1.5)),
                ),
              ]),
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            row('Ctrl+S', 'حفظ — الزر الرئيسي في الشاشة الحالية'),
            row('Ctrl+P', 'طباعة'),
            row('Ctrl+N', 'سند/طلبية جديدة — تعلّق الحالية وتفتح فارغة'),
            row('F5', 'تحديث البيانات'),
            row('Esc', 'إغلاق الحوار الحالي'),
            row('Enter', 'تأكيد في حوارات التأكيد'),
          ],
        );
      },
      actions: (ctx) => [
        ImdButton(label: 'إغلاق', onPressed: () => Navigator.of(ctx).pop()),
      ],
    );
  }
}
