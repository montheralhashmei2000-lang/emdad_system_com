/// تعديل وإلغاء المستندات المحفوظة — نقل مطابق لمنطق documents-center.js.
/// القاعدة: عند تعديل سند معتمد يُطبَّق **فرق الكميات فقط** على الأرصدة،
/// وعند الإلغاء يُعكس أثر السند كاملًا. المسودات والأوامر المعلقة بلا أثر مخزني.
library;

enum DocumentType { receipt, issue, transfer, returnDoc }

class DocumentLine {
  const DocumentLine({required this.itemId, required this.baseQty});

  final String itemId;
  final double baseQty;
}

class DocumentContext {
  const DocumentContext({
    required this.type,
    required this.status,
    this.returnType = 'FROM_UNIT', // FROM_UNIT | TO_SUPPLIER
    this.condition = 'صالحة',
  });

  final DocumentType type;
  final String status;
  final String returnType;
  final String condition;

  /// اتجاه أثر السند على رصيد المستودع: +1 يزيد، −1 ينقص، 0 بلا أثر.
  int get sign {
    switch (type) {
      case DocumentType.receipt:
        return status == 'COMPLETED' ? 1 : 0;
      case DocumentType.issue:
        return status == 'COMPLETED' ? -1 : 0;
      case DocumentType.transfer:
        return 0; // التحويل لا يغيّر الإجمالي، وأثره على المستودعين يُحسب في دفتر الأرصدة
      case DocumentType.returnDoc:
        if (status == 'CANCELLED') return 0;
        if (returnType == 'TO_SUPPLIER') return -1;
        return condition == 'تالفة' ? 0 : 1;
    }
  }

  bool get editable => type != DocumentType.transfer || status == 'PENDING';
}

class DocumentEdit {
  /// أثر مجموعة سطور على الأرصدة حسب اتجاه السند.
  static Map<String, double> effect(List<DocumentLine> lines, int sign) {
    if (sign == 0) return const {};
    final out = <String, double>{};
    for (final l in lines) {
      if (l.itemId.isEmpty) continue;
      out[l.itemId] = _round((out[l.itemId] ?? 0) + sign * l.baseQty);
    }
    return out;
  }

  /// فرق التعديل = أثر السطور الجديدة − أثر السطور القديمة.
  static Map<String, double> delta({
    required DocumentContext context,
    required List<DocumentLine> before,
    required List<DocumentLine> after,
  }) {
    final sign = context.sign;
    final b = effect(before, sign);
    final a = effect(after, sign);
    final keys = <String>{...b.keys, ...a.keys};
    final out = <String, double>{};
    for (final k in keys) {
      final v = _round((a[k] ?? 0) - (b[k] ?? 0));
      if (v != 0) out[k] = v;
    }
    return out;
  }

  /// أثر الإلغاء: عكس أثر السند الحالي.
  static Map<String, double> cancellation({
    required DocumentContext context,
    required List<DocumentLine> lines,
  }) {
    final eff = effect(lines, context.sign);
    return eff.map((k, v) => MapEntry(k, _round(-v)));
  }

  /// فحص أن التعديل لا يجعل رصيد أي صنف سالبًا.
  static EditCheck check({
    required Map<String, double> delta,
    required Map<String, double> availableBaseQty,
  }) {
    for (final e in delta.entries) {
      if (e.value >= 0) continue;
      final have = availableBaseQty[e.key] ?? 0;
      if (have + e.value < -1e-9) {
        return EditCheck(ok: false, itemId: e.key, available: have, needed: -e.value);
      }
    }
    return const EditCheck(ok: true);
  }

  static double _round(double v) => (v * 1000).round() / 1000;
}

class EditCheck {
  const EditCheck({required this.ok, this.itemId = '', this.available = 0, this.needed = 0});

  final bool ok;
  final String itemId;
  final double available;
  final double needed;
}
