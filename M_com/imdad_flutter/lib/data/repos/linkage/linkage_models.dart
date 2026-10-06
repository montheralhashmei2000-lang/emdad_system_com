import 'dart:convert';
import 'package:flutter/material.dart' show DateUtils;
import '../../../core/ui/imd_widgets.dart' show ImdTone;
import '../../../domain/finance.dart';
import '../../db/app_database.dart';

/// حالات الفرد وبياناتها للعرض — المصدر الوحيد للمفاتيح والنبرات.
class LinkStatus {
  static const String present = 'present';
  static const String absent = 'absent';
  static const String mission = 'mission';
  static const String leave = 'leave';
  static const String permission = 'permission';
  static const String deserter = 'deserter';

  /// المفتاح ⇒ (التسمية، النبرة).
  static const Map<String, (String, ImdTone)> meta = {
    present: ('موجود', ImdTone.ok),
    absent: ('غياب', ImdTone.pend),
    mission: ('مهمة', ImdTone.info),
    leave: ('إجازة', ImdTone.code),
    permission: ('إذن', ImdTone.pend),
    deserter: ('فرار', ImdTone.err),
  };

  /// حالات «ذات مدى» تُؤرَّخ من/إلى — «موجود» لا يحتاج مدى.
  static const List<String> dated = [absent, mission, leave, permission, deserter];

  /// الحالات المضافة من المستخدم (مثل «مريض مستشفى») تُحفظ في دليل المسميات
  /// (`link_terms` نوع `status`) ويكون **اسمها هو مفتاحها**، فتُعرض كما كُتبت
  /// وتبقى سجلات الأفراد سليمةً لو حُذفت من الدليل. وهي كلها ذات مدى.
  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.info;
  static bool isDated(String s) => s.isNotEmpty && s != present;
}


/// عملة فاتورة الشراء.
class LinkCurrency {
  static const String sar = 'sar';
  static const String yer = 'yer';

  static const Map<String, String> labels = {sar: 'سعودي', yer: 'يمني'};

  static String label(String c) => labels[c] ?? c;

  /// الاسم في التفقيط: «ريال يمني».
  static String major(String c) => c == yer ? 'ريال يمني' : 'ريال سعودي';

  /// الوحدة الصغرى في التفقيط.
  static String minor(String c) => c == yer ? 'فلس' : 'هللة';

  /// رمز العملة في الجداول المطبوعة.
  static String symbol(String c) => c == yer ? 'ر.ي.' : 'ر.س.';
}


/// سطر أصناف في عقد الشراء. نصٌّ حر بلا صلة بأصناف النظام.
class ContractItem {
  const ContractItem({
    this.name = '',
    this.unit = '',
    this.qty = 0,
    this.price = 0,
    this.total = 0,
    this.invoiceNo = '',
    this.date = '',
    this.note = '',
  });

  final String name;
  final String unit;
  final double qty;
  final double price;

  /// السعر الإجمالي — يُحسب افتراضيًّا (الكمية × السعر) ويقبل التعديل.
  final double total;
  final String invoiceNo;

  /// تاريخ الشراء حسب الفاتورة (يدوي).
  final String date;
  final String note;

  bool get isEmpty =>
      name.trim().isEmpty && unit.trim().isEmpty && qty == 0 && price == 0 && total == 0 && invoiceNo.trim().isEmpty && note.trim().isEmpty;

  /// الإجمالي الافتراضي: الكمية × سعر الوحدة (الكمية الفارغة تُعدّ واحدًا).
  static double autoTotal(double qty, double price) => (qty > 0 ? qty : 1) * price;

  Map<String, Object> toJson() => {
        'name': name,
        'unit': unit,
        'qty': qty,
        'price': price,
        'total': total,
        'invoiceNo': invoiceNo,
        'date': date,
        'note': note,
      };

  static double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static List<ContractItem> decode(String json) {
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map)
            ContractItem(
              name: '${e['name'] ?? ''}',
              unit: '${e['unit'] ?? ''}',
              qty: _d(e['qty']),
              price: _d(e['price']),
              total: _d(e['total']),
              invoiceNo: '${e['invoiceNo'] ?? ''}',
              date: '${e['date'] ?? ''}',
              note: '${e['note'] ?? ''}',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<ContractItem> items) =>
      jsonEncode([for (final i in items) if (!i.isEmpty) i.toJson()]);

  /// إجمالي القائمة.
  static double sum(Iterable<ContractItem> items) => items.fold(0.0, (s, e) => s + e.total);
}


/// أنواع الإخلاء.
class LinkClearanceKind {
  static const String custody = 'custody';
  static const String contract = 'contract';
  static const String other = 'other';

  static const Map<String, (String, ImdTone)> meta = {
    custody: ('عهدة', ImdTone.code),
    contract: ('عقد', ImdTone.info),
    other: ('حر', ImdTone.off),
  };

  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.off;
}


/// حالات عقد المشتريات.
class LinkContractStatus {
  static const String open = 'open';
  static const String done = 'done';
  static const String canceled = 'canceled';

  static const Map<String, (String, ImdTone)> meta = {
    open: ('قيد التنفيذ', ImdTone.info),
    done: ('منفَّذ', ImdTone.ok),
    canceled: ('ملغى', ImdTone.err),
  };

  static String label(String s) => meta[s]?.$1 ?? s;
  static ImdTone tone(String s) => meta[s]?.$2 ?? ImdTone.off;
}


/// إجراء العودة من إجازة/غياب.
const List<String> kLinkReturnActions = ['مواصلة عمل', 'مباشرة عمل'];


/// عدد أيام مدىٍ مؤرَّخ — شاملُ الطرفين (إجازة من 5 إلى 5 = يومٌ واحد).
int linkDaysBetween(String fromIso, String toIso) {
  final a = DateTime.tryParse(fromIso);
  final b = DateTime.tryParse(toIso);
  if (a == null || b == null) return 0;
  final d = DateUtils.dateOnly(b).difference(DateUtils.dateOnly(a)).inDays + 1;
  return d > 0 ? d : 0;
}


/// سجلات فردٍ مرتبطة به — التسليح فقط: العهد والعقود والإخلاءات مالية الإمداد
/// وليست مرتبطةً بالأفراد.
typedef LinkPersonRecords = ({List<LinkArmament> armaments});


/// نوع التنبيه.
enum LinkAlertType {
  deserter,
  statusExpired,
  statusEnding,
  custodyOverdue,
  contractExpired,
  contractEnding,
}


/// شدة التنبيه.
enum LinkAlertSeverity { critical, high, medium, low }


/// تنبيه ذكي مرتبط بالقوة البشرية أو المالية أو العقود.
class LinkAlert {
  const LinkAlert({
    required this.type,
    required this.severity,
    required this.title,
    required this.body,
    this.personId = '',
    this.personName = '',
    this.relatedId = '',
  });

  final LinkAlertType type;
  final LinkAlertSeverity severity;
  final String title;
  final String body;
  final String personId;
  final String personName;
  final String relatedId;
}


/// رقم فاتورة العقد: المكتوب في رأس العقد، وإلا أول رقمٍ في أسطر الأصناف
/// (عقودٌ حُفظت قبل وجود الحقل).
extension LinkContractInvoice on LinkPurchaseContract {
  String get displayInvoiceNo {
    if (invoiceNo.trim().isNotEmpty) return invoiceNo.trim();
    for (final i in ContractItem.decode(itemsJson)) {
      if (i.invoiceNo.trim().isNotEmpty) return i.invoiceNo.trim();
    }
    return '';
  }

  /// هل رقم الفاتورة [no] هو رقم هذا العقد (بلا فرق حالة أحرف أو فراغات)؟
  bool matchesInvoice(String no) {
    final v = no.trim().toLowerCase();
    if (v.isEmpty) return false;
    return displayInvoiceNo.toLowerCase() == v ||
        ContractItem.decode(itemsJson).any((i) => i.invoiceNo.trim().toLowerCase() == v);
  }
}


/// منعٌ مقصود لعمليةٍ ماليةٍ مخالفةٍ للقواعد (تكرار رقم، حذف مرتبط…). رسالته
/// عربية مقروءة تُعرض للمستخدم كما هي.
class LinkBlocked implements Exception {
  const LinkBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}


/// استهلاك عهدة: مجموع عقودها بعملتها، وعددها، وما تعذّر تحويله.
class CustodyUsage {
  const CustodyUsage({this.consumed = 0, this.contracts = 0, this.unconvertible = 0});
  final double consumed;
  final int contracts;
  final int unconvertible;
}


/// تسوية عهدة: ما خُصِّص وما صُرف وما أُرجع، والفرق وطرفه المقابل.
class CustodySettlement {
  const CustodySettlement({
    required this.custody,
    required this.granted,
    required this.spent,
    required this.returned,
    required this.sheets,
    required this.diff,
    required this.counterparty,
  });

  final LinkFinCustody custody;
  final double granted;
  final double spent;
  final double returned;

  /// عدد مسيرات العهدة — صفر يعني أن المصروف صفر لأنه لم يُسجَّل لا لأنه لم يقع.
  final int sheets;
  final CustodyDiff diff;
  final String counterparty;
}


/// سطر في كشف حساب مالية.
class StatementLine {
  const StatementLine({required this.date, required this.label, required this.delta, required this.currency, required this.kind});
  final String date;
  final String label;
  final double delta;
  final String currency;
  final String kind;
}


class PartyStatement {
  const PartyStatement({required this.party, required this.lines, required this.balance});
  final String party;
  final List<StatementLine> lines;

  /// الرصيد لكل عملة: الموجب لصاحب العهدة (دائن)، والسالب عليه (مدين).
  final Map<String, double> balance;
}
