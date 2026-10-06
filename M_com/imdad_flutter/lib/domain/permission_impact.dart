import 'dart:convert';

import '../core/error_log.dart';
import '../data/db/app_database.dart';
import 'access_control.dart';

/// بند في تقرير الأثر: مجموعةُ مستخدمين وما يتغيّر عليهم.
class ImpactItem {
  const ImpactItem(this.id, this.title, this.effect, this.users);

  final String id;
  final String title;

  /// ماذا يحدث لهؤلاء المستخدمين بعد نقل الصلاحيات الخاصة إلى المالك.
  final String effect;
  final List<User> users;
}

/// تقرير أثر نقل الصلاحيات الخاصة (`sys.*`) إلى المالك — **قراءةٌ فقط**.
///
/// يجيب قبل أي ترحيل نهائي: من سيفقد ماذا؟ لا يغيّر شيئًا في أي حساب، وقرار
/// ما يُفعل بكل مجموعة (إبقاء، ترقية، سحب) للمالك.
class PermissionImpact {
  const PermissionImpact._();

  static Map<String, dynamic> _perms(User u) {
    try {
      final v = jsonDecode(u.permissions);
      if (v is Map) return v.cast<String, dynamic>();
    } catch (e, st) {
      // مصفوفةُ صلاحياتٍ تالفة تُعامل «بلا صلاحيات» في التقرير؛ يُسجَّل العطب لا يُبتلع.
      ErrorLogger.log('permission_impact', e, st);
    }
    return const {};
  }

  static bool _has(User u, String page, String action) {
    final p = _perms(u)[page];
    return p is Map && p[action] == true;
  }

  static bool _isUser(User u) => !UserRole.isAdmin(u.role);

  /// يبني التقرير من قائمة المستخدمين.
  static List<ImpactItem> build(List<User> all) {
    final nonAdmins = all.where(_isUser).toList();
    return [
      ImpactItem(
        'admins',
        'مديرو النظام الحاليون',
        'يفقدون النسخ الاحتياطي والاستعادة، وتفعيل الأجهزة، والمزامنة والاقتران، '
            'والإعدادات الحساسة (قواعد المحرك ومفتاح التوقيع والأرشفة التلقائية)، '
            'ومنح دور المدير وتعطيل الحسابات وتعديل الصلاحيات — فتصير للمالك وحده.',
        [for (final u in all) if (u.role == UserRole.admin) u],
      ),
      ImpactItem(
        'settingsEditors',
        'مستخدمون عاديون يملكون «الإعدادات: تعديل»',
        'كانوا يستعيدون النسخ ويحفظون قواعد المحرك ويديرون مفتاح التوقيع ويقترنون '
            'بالمزامنة. يفقدون هذه الإجراءات؛ ويبقى لهم الهوية والنماذج والطباعة واستيراد Excel.',
        [for (final u in nonAdmins) if (_has(u, 'settings', PermAction.edit)) u],
      ),
      ImpactItem(
        'usersAccess',
        'مستخدمون عاديون يملكون «المستخدمون والصلاحيات»',
        'لا تُفتح لهم شاشة المستخدمين أصلًا (للمديرين)، لكن صلاحيتهم المخزَّنة لا أثر لها '
            'بعد الآن: تعديل الصلاحيات وإدارة الحسابات للمالك والمدير فقط.',
        [
          for (final u in nonAdmins)
            if (_has(u, 'usersAccess', PermAction.view) ||
                _has(u, 'usersAccess', PermAction.edit) ||
                _has(u, 'usersAccess', PermAction.approve))
              u,
        ],
      ),
      ImpactItem(
        'suppliersCreateOnly',
        'مستخدمون يملكون «الموردون: إضافة» بلا «تعديل»',
        'صارت الحراسة بصلاحية الموردين نفسها (بدل المدير وحده). لا رفعٌ تلقائي: يضيفون '
            'موردين جددًا ولا يعدّلون القائم — راجع إن كان ذلك مقصودًا.',
        [
          for (final u in nonAdmins)
            if (_has(u, 'suppliers', PermAction.create) && !_has(u, 'suppliers', PermAction.edit)) u,
        ],
      ),
      ImpactItem(
        'storesCreateOnly',
        'مستخدمون يملكون «المستودعات: إضافة» بلا «تعديل»',
        'كما في الموردين: الحراسة بصلاحية المستودعات نفسها، بلا رفعٍ تلقائي.',
        [
          for (final u in nonAdmins)
            if (_has(u, 'stores', PermAction.create) && !_has(u, 'stores', PermAction.edit)) u,
        ],
      ),
      ImpactItem(
        'importInherit',
        'مستخدمون يرثون «استيراد» من «إضافة»',
        'لم يُحدَّد لهم `import` صراحةً، فيرثون «إضافة» على الأصناف والارتباطات '
            '(توافقٌ لئلا يفقدوا ما كان لهم). حدّد لكلٍّ منهم `import` صراحةً إن أردت التمييز.',
        [
          for (final u in nonAdmins)
            if (['items', 'linkages'].any((p) {
              final m = _perms(u)[p];
              return m is Map && m['create'] == true && !m.containsKey(PermAction.import);
            }))
              u,
        ],
      ),
    ];
  }
}
