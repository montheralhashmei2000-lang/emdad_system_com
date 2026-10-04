import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../domain/access_control.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';
import 'linkages_screen.dart' show LinkPersonnelTab, LinkTermsPanel;

/// شاشة **القوة البشرية للإمداد والتموين**.
///
/// تبويباتها داخل الشاشة: «الأفراد» (القائمة وحالاتهم) و«المسميات والحالات»
/// (الوحدات الفرعية والأقسام والأعمال والحالات المضافة). وتنبيهاتها (فرار،
/// انتهاء إجازة/مهمة…) في جرس التنبيهات بالشريط العلوي.
/// الصلاحية: صفحة `personnel`.
class PersonnelStrengthScreen extends StatefulWidget {
  const PersonnelStrengthScreen({super.key});

  @override
  State<PersonnelStrengthScreen> createState() => _PersonnelStrengthScreenState();
}

class _PersonnelStrengthScreenState extends State<PersonnelStrengthScreen> {
  String _tab = 'persons';

  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    if (!perm.has('personnel') && !perm.has('linkages')) {
      return const ImdPage(children: [ImdPanel(child: ImdEmptyState.noPermission())]);
    }
    final repo = LinkageRepo(context.read<AppDatabase>());
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'القوة البشرية للإمداد والتموين',
        icon: 'users',
        subtitle: 'شؤون أفراد الإمداد والتموين مع بحث مؤجَّل وتحديد جماعي وحالاتٍ قابلة للإضافة',
      ),
      ImdSegmented<String>(
        tabs: const [
          ImdTab('persons', 'الأفراد', icon: 'users'),
          ImdTab('terms', 'المسميات والحالات', icon: 'sliders'),
        ],
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
      ),
      const SizedBox(height: 12),
      if (_tab == 'persons')
        LinkPersonnelTab(repo: repo, perm: perm)
      else
        ImdPanel(child: LinkTermsPanel(repo: repo, canEdit: perm.has('personnel', PermAction.edit))),
    ]);
  }
}
