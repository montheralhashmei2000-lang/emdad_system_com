part of '../stocktake_screen.dart';

const _types = <String, String>{
  'FULL': 'جرد كامل',
  'PARTIAL': 'جرد جزئي (تصنيف)',
  'SURPRISE': 'جرد مفاجئ',
  'CYCLE': 'جرد دوري',
};

const _statuses = <String, String>{
  'COUNTING': 'قيد التنفيذ',
  'CLOSED': 'معتمد ومغلق',
  'CANCELLED': 'ملغى',
};

ImdTone _statusTone(String s) => switch (s) {
      'COUNTING' => ImdTone.pend,
      'CLOSED' => ImdTone.ok,
      'CANCELLED' => ImdTone.off,
      _ => ImdTone.code,
    };

const _reasons = <String>[
  '',
  'تلف',
  'فقد / عجز',
  'خطأ في الإدخال',
  'حركة غير مسجلة',
  'خطأ في وحدة القياس',
  'زيادة غير مبررة',
  'أخرى',
];

const _decisions = <String, String>{
  'ADJUST': 'تسوية الرصيد',
  'IGNORE': 'تجاهل الفرق',
  'RECOUNT': 'إعادة العد',
};

/// الفرق بإشارته كما في `SG()`.
String _sg(double n) {
  final v = (n * 1000).round() / 1000;
  return '${v > 0 ? '+' : (v < 0 ? '-' : '')}${nf(v.abs())}';
}
