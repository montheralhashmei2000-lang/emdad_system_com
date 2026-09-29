import 'package:flutter/material.dart';

import 'imd_icon.dart';

/// حالة «لا شيء لعرضه»: أيقونة كبيرة فوق عنوان ونص مساعد وزر إجراء اختياري.
///
/// تصلح للشاشة كلها أو لقسمٍ صغير أو لجدولٍ فارغ. أمّا [ImdEmptyBox] فيبقى صفَّ
/// نصٍّ داخل إطار جدول للاستعمالات القائمة.
///
/// الأيقونات من مكتبة `ImdIcon` لا من `Icons` في Material،
/// وليس فيها `inbox` ولا `search_off`، فأقربُ بدائلها: `package` و`search`.
class ImdEmptyState extends StatelessWidget {
  const ImdEmptyState({
    super.key,
    required this.title,
    required this.icon,
    this.message,
    this.action,
  });

  /// لا توجد بيانات بعد.
  const ImdEmptyState.noData({
    super.key,
    this.title = 'لا توجد بيانات',
    this.message,
    this.action,
  }) : icon = 'package';

  /// بحثٌ أو تصفيةٌ لم تُرجع شيئًا.
  const ImdEmptyState.noResults({
    super.key,
    this.title = 'لا توجد نتائج',
    this.message = 'جرّب تغيير كلمات البحث أو إزالة عوامل التصفية.',
    this.action,
  }) : icon = 'search';

  /// فشل تحميل أو عملية.
  const ImdEmptyState.error({
    super.key,
    this.title = 'حدث خطأ',
    this.message,
    this.action,
  }) : icon = 'alert';

  /// المستخدم لا يملك صلاحية العرض.
  const ImdEmptyState.noPermission({
    super.key,
    this.title = 'لا تملك صلاحية العرض',
    this.message = 'تواصل مع مدير النظام إن كنت تحتاج هذا الوصول.',
    this.action,
  }) : icon = 'lock';

  /// حالة مخصصة: أيّ أيقونةٍ من مكتبة `ImdIcon`.
  const ImdEmptyState.custom({
    super.key,
    required this.title,
    required this.icon,
    this.message,
    this.action,
  });

  final String title;

  /// اسم أيقونة `ImdIcon`.
  final String icon;
  final String? message;

  /// عادةً `ImdButton`.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasMessage = message != null && message!.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        // سقفٌ لعرض النص كي لا تمتد الأسطر على شاشةٍ عريضة؛ ويضيق مع الشاشة الضيقة.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ImdIcon(icon, size: 64, color: scheme.onSurface.withValues(alpha: .4), strokeWidth: 1.5),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (hasMessage) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
