import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/security/perm.dart';
import '../../core/ui/imd_empty_state.dart';
import '../../core/ui/imd_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/linkage_repo.dart';
import 'linkages_screen.dart' show LinkPersonnelTab;

/// شاشة **القوة البشرية للإمداد والتموين** — الواجهة المستقلة (النسخة Pro).
///
/// نفس بيانات تبويب القوة داخل «مركز الارتباطات» بلا نسخةٍ ثانية.
/// الصلاحية: صفحة `personnel`.
class PersonnelStrengthScreen extends StatelessWidget {
  const PersonnelStrengthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = Perm.of(context);
    if (!perm.has('personnel') && !perm.has('linkages')) {
      return const ImdPage(children: [ImdPanel(child: ImdEmptyState.noPermission())]);
    }
    return ImdPage(children: [
      const ImdPageTitle(
        title: 'القوة البشرية للإمداد والتموين',
        icon: 'users',
        subtitle:
            'شؤون أفراد الإمداد والتموين مع تنبيهات ذكية وبحث مؤجَّل وتحديد جماعي — '
            'والتسليح مرتبط بكل فردٍ من مركز الارتباطات (أمّا المالية فبالعهد والإخلاءات والعقود)',
      ),
      LinkPersonnelTab(
          repo: LinkageRepo(context.read<AppDatabase>()), perm: perm),
    ]);
  }
}
