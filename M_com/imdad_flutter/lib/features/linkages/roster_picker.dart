import 'package:flutter/material.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import 'roster_tables.dart';

/// نافذة «اختر الجداول المراد طباعتها» للكشف. تُعيد المفاتيح المختارة، أو
/// `null` عند الإلغاء. الكشف الكامل مختارٌ افتراضيًّا.
Future<Set<String>?> pickRosterTables(BuildContext context, List<LinkPerson> persons) {
  final options = rosterOptions(persons);
  final selected = <String>{rosterFullKey};
  return showImdModal<Set<String>>(
    context,
    title: 'اختر الجداول المراد طباعتها',
    icon: 'printer',
    maxWidth: 520,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final c = ctx.imd;
        final groups = <String>[];
        for (final o in options) {
          if (!groups.contains(o.group)) groups.add(o.group);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ImdButton.outline(
                label: 'تحديد الكل', small: true, onPressed: () => setLocal(() => selected.addAll(options.map((o) => o.key)))),
            ImdButton.outline(label: 'إلغاء التحديد', small: true, onPressed: () => setLocal(selected.clear)),
          ]),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(g, style: TextStyle(fontWeight: FontWeight.w700, color: c.muted, fontSize: 12.5)),
            ),
            for (final o in options.where((o) => o.group == g))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: ImdCheckbox(
                  value: selected.contains(o.key),
                  label: o.hint.isEmpty ? o.title : '${o.title} — ${o.hint}',
                  onChanged: (v) => setLocal(() => v ? selected.add(o.key) : selected.remove(o.key)),
                ),
              ),
          ],
        ]);
      },
    ),
    actions: (ctx) => [
      ImdButton.outline(label: 'إلغاء', onPressed: () => Navigator.of(ctx).pop()),
      ImdButton(
        label: 'طباعة المحدد',
        icon: 'printer',
        onPressed: () {
          if (selected.isEmpty) {
            showImdToast(ctx, '✖ حدّد جدولًا واحدًا على الأقل', error: true);
            return;
          }
          Navigator.of(ctx).pop({...selected});
        },
      ),
    ],
  );
}
