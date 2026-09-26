/// أبواب القائمة: بندٌ واحد يفتح شاشةً بتبويبات.
///
/// **الباب يُفتح لمن ملك إحدى تبويباته**، والتبويبة تُخفى عمّن لا يملكها —
/// فالجمع تنظيمٌ للقائمة لا توسيعٌ للأذونات.
library;

/// تبويبات كل باب، بمعرّفات صلاحياتها.
const Map<String, List<String>> kMenuDoors = {
  // الإمداد والتموين
  'supplyMoves': ['receive', 'issue', 'transfer', 'returns', 'opening'],
  'supplyOrders': ['rationOrders', 'pendingOrders'],
  'supplyData': ['items', 'stores', 'units', 'suppliers', 'kitchens', 'assets'],
  'supplyDaily': ['feeding', 'dailyOperations', 'ratios'],
  // التشغيل اليومي شاشةٌ بلا صلاحيةٍ خاصة: يراها من يملك الخطط أو سجل
  // المطبخ. وهو بابٌ داخل باب، ولا دور فيه فلا يتكرر الفحص.
  'dailyOperations': ['mealPlans', 'kitchenLog'],
  'supplyReports': ['reports', 'balances'],
  'supplyAudit': [
    'auditTrail',
    'activityIntel',
    'sensitiveOps',
    'executiveCmd',
    'healthOps',
  ],
  // المحروقات
  'fuelData': ['fuelWarehouses', 'fuelUnits', 'fuelVehicles'],
};

/// هل يُفتح [door] لمن تقول [can] بما يملك؟
///
/// **التبويبة التي تحمل اسم بابها تُتخطّى.** بابٌ يشير إلى نفسه يجعل الفحص
/// يستدعي نفسه بلا نهاية، فيفيض المكدّس وتسقط القائمة كلها — وفي نسخة
/// الإصدار تظهر مستطيلًا رماديًّا بلا رسالة. والحارس هنا أرخص من تتبّعٍ آخر.
bool menuDoorAllows(String door, bool Function(String page) can) {
  final tabs = kMenuDoors[door];
  if (tabs == null) return false;
  return tabs.any((p) => p != door && can(p));
}

/// أبوابٌ تشير إلى أنفسها — يجب أن تبقى فارغة.
///
/// تُقرأ في الاختبار لا في التشغيل: `assert` يُنزع من نسخة الإصدار، وهذا
/// العطل لا يظهر إلا فيها.
Iterable<String> selfReferencingDoors() =>
    kMenuDoors.entries.where((e) => e.value.contains(e.key)).map((e) => e.key);
