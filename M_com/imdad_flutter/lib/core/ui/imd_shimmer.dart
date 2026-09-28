import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'imd_layout.dart';
import 'imd_tokens.dart';

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

/// شريطٌ مصمَتٌ بزوايا 4 — الوحدة الأساسية لكل هياكل التحميل هنا. لونه غير
/// مهم فعليًّا: `Shimmer` يعيد رسمه بتدرّجه فوق شكله فقط، لا لون ودجاته.
Widget _imdShimmerBar(BuildContext context, {double? width, required double height}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: context.imd.subtle, borderRadius: BorderRadius.circular(4)),
    );

/// هيكل تحميلٍ لصفّ `ImdKpis`: بطاقاتٌ بنفس حجم `ImdKpi` وحشوته، بشريطين
/// مكان العنوان والقيمة، داخل `ImdAutoGrid` (نفس تكيّف الشبكة الحقيقية).
class ImdShimmerKpis extends StatelessWidget {
  const ImdShimmerKpis({super.key, this.count = 6});

  /// عدد بطاقات الهيكل — يُستحسن مطابقته لعدد `ImdKpi` الحقيقية القادمة.
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: ImdShimmer(
        child: ImdAutoGrid(minItem: 210, gap: 14, children: [
          for (var i = 0; i < count; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(ImdSizes.radius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _imdShimmerBar(context, width: 90, height: 10),
                  const SizedBox(height: 11),
                  _imdShimmerBar(context, width: 60, height: 22),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

/// هيكل تحميلٍ لـ `ImdTable`: نفس حاوية الجدول الحقيقية (حدّ وزوايا) برأسٍ
/// وصفوفٍ من أشرطة بعدد الأعمدة المطلوب، بدل انتظار البيانات بلا شكل.
class ImdShimmerTable extends StatelessWidget {
  const ImdShimmerTable({super.key, this.rows = 5, this.columns = 4});

  final int rows;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final c = context.imd;
    Widget cells(double barHeight) => Row(children: [
          for (var j = 0; j < columns; j++)
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: j == columns - 1 ? 0 : 16),
                child: _imdShimmerBar(context, height: barHeight),
              ),
            ),
        ]);
    return ImdShimmer(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(ImdSizes.radius),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: c.tableHead, border: Border(bottom: BorderSide(color: c.line))),
            child: cells(10),
          ),
          for (var i = 0; i < rows; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              decoration: BoxDecoration(
                border: i == rows - 1 ? null : Border(bottom: BorderSide(color: c.tableRowLine)),
              ),
              child: cells(13),
            ),
        ]),
      ),
    );
  }
}
