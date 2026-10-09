/// قوالب Excel الأربعة: الأصناف، الوحدات المستفيدة، الاستحقاق، تفريدة المعسكر.
///
/// **مصدرٌ واحد** لعناوين كل قالب وتعليماته: منه يُكتب التصدير، وبه يُكشف
/// الملف المستورَد، ومنه تُبنى ورقة «التعليمات» — فلا يختلف ما يُصدَّر عمّا
/// يُقبل استيرادًا.
library;

enum TemplateKind { items, units, entitlements, strength }

/// نمط الاستيراد على الموجود.
enum ImportMode {
  /// إضافة الجديد وتحديث الموجود (الافتراضي).
  merge,

  /// الملف هو المرجع: ما ليس فيه يُحذف إن جاز حذفه.
  replace,
}

class TemplateSpec {
  const TemplateSpec({
    required this.kind,
    required this.title,
    required this.headers,
    required this.detectKeys,
    required this.instructions,
  });

  final TemplateKind kind;

  /// اسم القالب كما يُعرض: «القالب المكتشَف: …».
  final String title;

  /// عناوين ورقة «البيانات» بترتيبها.
  final List<String> headers;

  /// العناوين التي بحضورها كلِّها يُعرف القالب (الإلزامية المميِّزة).
  final List<String> detectKeys;

  /// أسطر ورقة «التعليمات» — سطر في كل خلية.
  final List<String> instructions;

  static const String dataSheet = 'البيانات';
  static const String instructionsSheet = 'التعليمات';

  static const TemplateSpec items = TemplateSpec(
    kind: TemplateKind.items,
    title: 'الأصناف',
    headers: [
      'كود الصنف',
      'اسم الصنف',
      'التصنيف',
      'وحدة 1',
      'معامل 1',
      'وحدة 2',
      'معامل 2',
      'وحدة 3',
      'معامل 3',
      'رقم الوحدة الافتراضية',
    ],
    detectKeys: ['كود الصنف', 'اسم الصنف', 'وحدة 1'],
    instructions: [
      'قالب الأصناف — ورقة «البيانات» صفٌّ لكل صنف، وصف العناوين الأول لا يُغيَّر.',
      'كود الصنف: مطلوب، فريد، أرقام فقط',
      'اسم الصنف: مطلوب',
      'التصنيف: اختياري، يُنشَأ تلقائياً إن لم يكن موجوداً',
      'وحدة 1: مطلوبة، وهي الوحدة الصغرى (وحدة الأساس)',
      'معامل 1: افتراضي 1 — ويجب أن يساوي 1 إن كُتب',
      'وحدة 2: اختيارية',
      'معامل 2: سعة وحدة 2 من وحدة 1 — مثال: كرتون = 12 حبة',
      'وحدة 3: اختيارية',
      'معامل 3: سعة وحدة 3 من وحدة 1 — مثال: كرتون = 12 علبة = 144 حبة',
      'رقم الوحدة الافتراضية: 1 أو 2 أو 3 — تُعتمد وحدةً للتقارير، ويجب أن تكون وحدتها مكتوبة',
      'عند الدمج: يُحدَّث الصنف بكوده ويُضاف الجديد. وصنفٌ له حركات لا تتغيّر وحداته (يُذكر ذلك في التقرير).',
    ],
  );

  static const TemplateSpec units = TemplateSpec(
    kind: TemplateKind.units,
    title: 'الوحدات المستفيدة',
    headers: ['الكود', 'الاسم', 'الاختصاص'],
    detectKeys: ['الكود', 'الاسم', 'الاختصاص'],
    instructions: [
      'قالب الوحدات المستفيدة — ورقة «البيانات» صفٌّ لكل وحدة.',
      'الكود: مطلوب، يُنشئ التسلسل الهرمي تلقائياً',
      'الاسم: مطلوب',
      'الاختصاص: أحد الخمسة (معسكر، وحدة، وحدات إدارية، الشعبة الفنية، نقاط)، وإن تُرك فارغاً فهو «وحدة»',
      'البنية: كود بدون "-" = جذر (معسكر أو نقاط)، وكود بـ"-" = فرع للجذر السابق',
      'مثال: 1 = معسكر، و1-1 و1-2 فرعان له، و2 معسكر جديد، و4 نقاط و4-1 فرع له',
      'مستويان فقط: جذر وفرع. كود مثل 1-1-1 يُرفض.',
      'الفرع يحتاج جذره: إما في الملف أو موجوداً مسبقاً بالكود نفسه.',
    ],
  );

  static const TemplateSpec entitlements = TemplateSpec(
    kind: TemplateKind.entitlements,
    title: 'الاستحقاق',
    headers: ['كود الصنف', 'اسم الصنف', 'وحدة الاستحقاق', 'الكمية للفرد بالشهر'],
    detectKeys: ['كود الصنف', 'اسم الصنف', 'وحدة الاستحقاق', 'الكمية للفرد بالشهر'],
    instructions: [
      'قالب الاستحقاق — ورقة «البيانات» صفٌّ لكل صنف.',
      'كود الصنف: يجب أن يكون موجوداً',
      'اسم الصنف: يجب أن يطابق الصنف',
      'وحدة الاستحقاق: من وحدات الصنف (مثل: جرام، علبة، كرتون)',
      'الكمية للفرد بالشهر: رقم عشري ≥ 0، بوحدة الاستحقاق المختارة',
    ],
  );

  static const TemplateSpec strength = TemplateSpec(
    kind: TemplateKind.strength,
    title: 'تفريدة المعسكر',
    headers: ['اسم الوحدة', 'القوة الفعلية', 'نسبة الزيادة', 'الإجمالي'],
    detectKeys: ['اسم الوحدة', 'القوة الفعلية', 'نسبة الزيادة', 'الإجمالي'],
    instructions: [
      'قالب تفريدة المعسكر — يُحدَّد المعسكر والتاريخ عند الاستيراد، لا في الملف.',
      'اسم الوحدة: من الوحدات المستفيدة (أبناء المعسكر المختار)',
      'القوة الفعلية: عدد صحيح ≥ 0',
      'نسبة الزيادة: رقم (عادة 10%) — هو عدد أفراد الزيادة، وليس النسبة المئوية',
      'الإجمالي: يُحسب تلقائياً = القوة الفعلية + نسبة الزيادة',
      'صف الإجمالي النهائي: معادلات SUM لكل عمود',
    ],
  );

  static const List<TemplateSpec> all = [items, units, entitlements, strength];

  static TemplateSpec of(TemplateKind k) => all.firstWhere((s) => s.kind == k);
}

/// تطبيع نصّ العنوان للمقارنة: ألفات وتاء مربوطة وأرقام ومسافات.
String normalizeHeader(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + (r - 0x0660));
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + (r - 0x06F0));
    } else if (r == 0x200F || r == 0x200E || r == 0x061C || r == 0x200D || r == 0x200C || r == 0x0640) {
      continue;
    } else {
      b.writeCharCode(r);
    }
  }
  return b
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// أرقام لاتينية → هندية، لنصوص ورقة «التعليمات» (أرقام البيانات تبقى لاتينية).
String arabicDigits(String s) {
  const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.write(ar[r - 0x30]);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}
