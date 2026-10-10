import 'package:flutter/widgets.dart';

/// علامة «عدّل المستخدم شيئًا في هذه الصفحة» — واحدةٌ لكل صفحةٍ مفتوحة.
///
/// القشرة تُعيد بناء الصفحة المخفيّة التي تغيّرت بياناتها حين يعود إليها
/// المستخدم، **إلا** إن كان قد كتب فيها أو اختار: إعادة البناء تمحو سندًا نصف
/// مملوء وتبويبات السندات المعلّقة. فتبقى تلك الصفحة كما هي، بنقطةٍ على تبويبها.
///
/// تُرفع من حقول البيت نفسها ([ImdPageDirty.mark]) عند تعديلٍ **من المستخدم**:
/// `onChanged` في `TextField` ومنتقيات البيت لا يُطلق على التعبئة البرمجية.
/// ولا تُنزل إلا بإعادة بناء الصفحة أو إغلاقها: الشاشات لا تُبلغ عن الحفظ،
/// وتصفير النموذج بعده لا يعني أن لا سندات معلّقة في تبويباتها.
class ImdDirtyFlag {
  bool dirty = false;
}

class ImdPageDirty extends InheritedWidget {
  const ImdPageDirty({super.key, required this.flag, required super.child});

  final ImdDirtyFlag flag;

  /// يرفع علامة الصفحة المحيطة. بلا صفحةٍ محيطة (حوار، اختبار معزول) لا شيء.
  /// لا يُنشئ اعتمادًا: يُستدعى من معالجات الأحداث لا من `build`.
  static void mark(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ImdPageDirty>()?.flag.dirty = true;

  /// العلامة نفسها لتُرفع بعد `await` دون الرجوع إلى سياقٍ ربما فُكّ.
  static ImdDirtyFlag? flagOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ImdPageDirty>()?.flag;

  @override
  bool updateShouldNotify(ImdPageDirty oldWidget) => false;
}
