import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/imd_form.dart';
import '../../core/ui/imd_tokens.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/permission_impact.dart';

/// تقرير أثر نقل الصلاحيات الخاصة إلى المالك — للمالك، للقراءة فقط.
class PermissionImpactCard extends StatefulWidget {
  const PermissionImpactCard({super.key});

  @override
  State<PermissionImpactCard> createState() => _PermissionImpactCardState();
}

class _PermissionImpactCardState extends State<PermissionImpactCard> {
  late final AppDatabase _db = context.read<AppDatabase>();
  List<ImpactItem>? _items;

  @override
  void initState() {
    super.initState();
    _db.select(_db.users).get().then((all) {
      if (mounted) setState(() => _items = PermissionImpact.build(all));
    });
  }

  String _who(User u) => u.name.isNotEmpty ? '${u.name} (${u.username})' : u.username;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    final items = _items;
    return ImdPanel(
      title: 'تقرير أثر الصلاحيات الخاصة',
      icon: 'shield',
      child: items == null
          ? const ImdLd('⏳ جارٍ الحساب…')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const ImdNote('قراءةٌ فقط: من سيفقد ماذا بعد أن صارت النسخ الاحتياطية والتفعيل والمزامنة '
                  'والإعدادات الحساسة وتعديل الصلاحيات للمالك. لا يتغيّر شيءٌ بفتح هذا التقرير.'),
              for (final i in items) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: Text(i.title,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text))),
                  ImdChip('${i.users.length}', tone: i.users.isEmpty ? ImdTone.off : ImdTone.pend),
                ]),
                const SizedBox(height: 4),
                Text(i.effect, style: TextStyle(fontSize: 12.5, height: 1.8, color: c.muted)),
                if (i.users.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final u in i.users) ImdChip(_who(u), tone: ImdTone.info),
                    ]),
                  ),
              ],
            ]),
    );
  }
}
