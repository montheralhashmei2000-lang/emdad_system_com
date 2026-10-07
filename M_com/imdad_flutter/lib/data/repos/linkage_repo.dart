
import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show DateUtils;

import '../../core/ids.dart';
import '../../core/ui/imd_format.dart';
import '../../domain/custody_sheet.dart';
import '../../domain/finance.dart';
import 'doc_numbering.dart';
import 'finance_files.dart';
import '../db/app_database.dart';
import 'audit_repo.dart';
import '../../core/error_log.dart';

export 'linkage/linkage_models.dart';
import 'linkage/linkage_models.dart';

part 'linkage/persons_part.dart';
part 'linkage/custody_part.dart';
part 'linkage/custody_clearance_part.dart';
part 'linkage/contracts_part.dart';
part 'linkage/sheets_money_part.dart';
part 'linkage/armament_part.dart';


/// مستودع الارتباطات: القوة البشرية وحالاتها المؤرخة وإجراءات العودة،
/// ودليل المسميات (أقسام/أعمال/وحدات فرعية)، والعهد والإخلاءات، وعقود
/// المشتريات، والتسليح — وكل ارتباطٍ بالفرد بمعرّفه ولقطة اسمه ورقمه.
class LinkageRepo {
  LinkageRepo(this.db);

  final AppDatabase db;

  // الأعضاء الساكنة تبقى هنا: تُستدعى بصيغة `LinkageRepo.x`، وأعضاء الامتدادات الساكنة لا تُستدعى بها.
  /// القيم الافتراضية التي يُ seeded بها الدليل أول مرة.
  static const Map<String, List<String>> kDefaultTerms = {
    'section': ['مخزن', 'مطبخ', 'فرن', 'سائق', 'مكتب', 'مختص'],
    'job': ['معلم أرز', 'معلم مشكل', 'معلم شواية', 'معلم خباز', 'معلم عجان'],
    'subunit': ['إمداد', 'محروقات', 'مياه'],
    // الجهات المسؤولة عن العهد (مالية الإمداد).
    'holder': ['المستودع الرئيسي', 'المطبخ', 'الفرن', 'مكتب الإمداد', 'الورشة'],
  };

  static const String wfDraft = 'draft';
  static const String wfSent = 'sent';
  static const String wfApproved = 'approved';
  static const Map<String, String> workflowLabels = {wfDraft: 'مسودة', wfSent: 'مُرسل', wfApproved: 'مُعتمد'};

  static String partyOf(LinkFinCustody c) => c.receiverName.trim().isNotEmpty ? c.receiverName.trim() : c.holder.trim();

  /// ما يسحبه سطر المسير من عقد: التاريخ والفئة والمحل والمنصرف بعملة العقد وسعر الصرف.
  /// (المنصرف السعودي لعقدٍ يمني محسوبٌ فلا يدخل المقارنة.)
  static ({String date, String category, String shop, double amount, double rate, bool yer}) rowFromContract(LinkPurchaseContract k) =>
      (date: k.listDate, category: k.title.trim(), shop: k.supplier, amount: k.amount, rate: k.exchangeRate, yer: k.currency == LinkCurrency.yer);

  static String _d(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? (iso.isEmpty ? '—' : iso) : iso; // keep raw; UI formats
  }
}
