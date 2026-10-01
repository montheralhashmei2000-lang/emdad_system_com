import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// سجلّ إجراءات الشاشة النشطة — تسجّله كل شاشةٍ تريد الاستجابة لاختصارات
/// لوحة المفاتيح على سطح المكتب (Ctrl+S حفظ، Ctrl+P طباعة، Ctrl+N سند جديد،
/// F5 تحديث) في `initState`، وتُفرغه في `dispose`. طبقة الاختصارات العامة في
/// `main.dart` وشريط القوائم العلوي يستدعيانه بدل أن يعرفا بنفسهما أيّ شاشةٍ
/// نشطة الآن — بنفس فكرة `ImdNav` (التنقّل) لكن للإجراءات، وبنفس أسلوب
/// `.of(context)`/`Perm` في الوصول من أي مكان عبر `context.read`.
///
/// ليست `ChangeNotifier` عمدًا: شريط القوائم يقرأها لا يستمع إليها، فتُقرأ من
/// جديد مع كل إعادة بناءٍ لقالب الشاشة الرئيسية (كما يحدث عند كل تنقّل)، بلا
/// حاجةٍ لإشعارٍ فعلي ولا خطر استدعاء مستمعٍ أثناء تفكيك شجرة عنصرٍ جماعي.
class ImdScreenActions {
  VoidCallback? onSave;
  VoidCallback? onPrint;
  VoidCallback? onNewDoc;
  VoidCallback? onRefresh;

  /// تُستدعى في `initState` — الدوالّ غير المطلوبة تُترك `null` فلا يفعل
  /// اختصارها شيئًا، بدل أن تُفرَض دلالةٌ لا تملكها الشاشة.
  void register({
    VoidCallback? onSave,
    VoidCallback? onPrint,
    VoidCallback? onNewDoc,
    VoidCallback? onRefresh,
  }) {
    this.onSave = onSave;
    this.onPrint = onPrint;
    this.onNewDoc = onNewDoc;
    this.onRefresh = onRefresh;
  }

  /// تُستدعى في `dispose` — وإلا بقيت الشاشة المغلقة "نشطة" لاختصارات شاشةٍ
  /// غيرها فتحت بعدها.
  void clear() {
    onSave = null;
    onPrint = null;
    onNewDoc = null;
    onRefresh = null;
  }

  /// كـ`context.read<ImdScreenActions>()` لكن بلا رميٍ إن لم يُسجَّل السجلّ
  /// فوق الشجرة — شاشاتٌ في اختباراتٍ أو سياقاتٍ معزولةٍ عن `main.dart` لا
  /// تملك هذا المزوِّد، فيصحّ أن تُبنى بلا اختصارات بدل أن تنهار.
  static ImdScreenActions? maybeOf(BuildContext context) {
    try {
      return context.read<ImdScreenActions>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

/// اختصارات لوحة المفاتيح مدعومةٌ على سطح المكتب وحده — بلا أثرٍ على
/// الجوّال حتى مع لوحة مفاتيح خارجية متّصلة به.
class ImdShortcuts {
  ImdShortcuts._();

  static bool get supported =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}
