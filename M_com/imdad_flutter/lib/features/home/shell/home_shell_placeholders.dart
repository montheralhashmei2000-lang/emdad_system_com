part of '../home_shell.dart';

/// رسالة «صلاحية غير متاحة 🔒».
class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return const ImdPage(
      children: [
        ImdPageTitle(title: 'صلاحية غير متاحة', icon: 'lock'),
        ImdEmptyState.noPermission(
          message: 'لا تملك صلاحية الوصول إلى هذه الشاشة. اطلب من مدير النظام منحك الصلاحية المناسبة.',
        ),
      ],
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon();

  @override
  Widget build(BuildContext context) {
    return const ImdPage(
      children: [
        ImdPageTitle(
            title: 'قريبًا',
            icon: 'alert',
            subtitle: 'هذه الشاشة ستُبنى في خطوة قادمة'),
      ],
    );
  }
}
