import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// غلاف تحميل لامع (Skeleton) بألوان السمة.
///
/// يُلفّ حول أشكالٍ **مصمَتة** (حاويات بلون ما) تحاكي المحتوى القادم؛ فاللمعان
/// يُرسم على شكلها فقط. مثال: صفوف `Container` بزوايا 12 بدل جدولٍ يُحمَّل.
///
/// الألوان مشتقّة من `colorScheme.onSurface` فوق `surface` فتصلح في الفاتح والداكن
/// وسمة المحروقات. ويسير اللمعان مع اتجاه القراءة (يمين→يسار في RTL).
class ImdShimmer extends StatelessWidget {
  const ImdShimmer({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// false ⇒ يُعرض [child] كما هو (للحالات التي يُستغنى فيها عن الحركة).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Shimmer.fromColors(
      baseColor: Color.alphaBlend(scheme.onSurface.withValues(alpha: .08), scheme.surface),
      highlightColor: Color.alphaBlend(scheme.onSurface.withValues(alpha: .16), scheme.surface),
      direction: rtl ? ShimmerDirection.rtl : ShimmerDirection.ltr,
      child: child,
    );
  }
}
