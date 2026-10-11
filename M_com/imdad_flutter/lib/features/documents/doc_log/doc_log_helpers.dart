part of '../doc_log_view.dart';

/// أنواع السندات المعروضة في السجل.
class _DocType {
  const _DocType(this.kind, this.label, this.icon, this.perm, this.partyLbl);
  final DocKind kind;
  final String label;
  final String icon;

  /// الشاشة التي تُشتق منها الصلاحية حين لا يملك المستخدم صلاحية `documents`.
  final String perm;
  final String partyLbl;
}

const _types = <_DocType>[
  _DocType(DocKind.receipt, 'استلام بضاعة', 'download', 'receive', 'المورد'),
  _DocType(DocKind.issue, 'صرف بضاعة', 'upload', 'issue', 'الجهة المستفيدة'),
  _DocType(DocKind.transfer, 'تحويل مخزني', 'repeat', 'transfer', 'إلى المستودع'),
  _DocType(DocKind.returnDoc, 'مرتجعات', 'undo', 'returns', 'الجهة'),
];

_DocType _typeOf(DocKind k) => _types.firstWhere((t) => t.kind == k);

/// `STATUS` و`STATUS_CHIP`.
const _statusLabels = <String, String>{
  'COMPLETED': 'معتمد',
  'DRAFT': 'مسودة',
  'ORDER': 'أمر معلق',
  'PENDING': 'قيد الاستلام',
  'RECEIVED': 'مستلم',
  'REJECTED': 'مرفوض',
  'CANCELLED': 'ملغى',
};

/// رسالة نقص الرصيد بنص `editDoc()`: «✖ الرصيد لا يكفي للصنف …».
String _stockMessage(EditCheck check, Item? item) => check.error.isNotEmpty
    ? check.error
    : '✖ الرصيد لا يكفي للصنف «${item?.name ?? check.itemId}»'
        '${check.warehouse.isEmpty ? '' : ' في مستودع «${check.warehouse}»'} (المتاح ${nf(check.available)})';

/// نص الكمية داخل حقل الإدخال — أرقام لاتينية كما في `input type=number`.
String _plain(double v) {
  final r = (v * 1000).round() / 1000;
  return r % 1 == 0 ? r.toInt().toString() : r.toString();
}

ImdTone _statusTone(String s) => switch (s) {
      'COMPLETED' || 'RECEIVED' => ImdTone.ok,
      'DRAFT' => ImdTone.off,
      'ORDER' || 'PENDING' => ImdTone.pend,
      'REJECTED' || 'CANCELLED' => ImdTone.err,
      _ => ImdTone.code,
    };
