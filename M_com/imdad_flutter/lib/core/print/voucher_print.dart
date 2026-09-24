import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/signatures_repo.dart';
import '../ui/imd_format.dart';
import 'military_print.dart';

/// سطر سند للطباعة.
class VoucherLine {
  const VoucherLine({
    required this.itemName,
    required this.unitName,
    required this.qty,
    this.itemCode = '',
    this.notes = '',
    this.beneficiary = '',
  });

  final String itemName;
  final String unitName;
  final double qty;
  final String itemCode;
  final String notes;

  /// الوحدة المستفيدة في الصرف متعدد الجهات.
  final String beneficiary;
}

/// نوع السند المطبوع — يحدد جدول البيانات وخانات التوقيع ولون العنوان.
enum VoucherKind { receive, issue, transfer, returnFromUnit, returnToSupplier }

/// طباعة السندات بمحرك الطباعة العسكرية الرسمية (`militaryPrint`).
class VoucherPrint {
  static Future<void> print({
    required AppDatabase db,
    required String title,
    required String refNo,
    required String date,
    required String warehouse,
    required List<VoucherLine> lines,
    VoucherKind kind = VoucherKind.receive,
    String party = '',
    String notes = '',
    String invoiceNo = '',
    String audit = '',
    String supervision = '',
    String statusLabel = '',
    String origRef = '',
    String condition = '',
    String strength = '',
    String days = '',
    String endDate = '',
    bool multiUnit = false,
    bool withReceipt = false,
  }) async {
    final engine = await engineOf(db);
    final master = <String, String>{
      'ref': refNo,
      'date': date,
      'start_date': date,
      'end_date': endDate,
      'warehouse': warehouse,
      'notes': notes,
      'invoiceNo': invoiceNo,
      'audit': audit,
      'supervision': supervision,
      'statusLabel': statusLabel,
      'origRef': origRef,
      'condition': condition,
      'strength': strength,
      'days': days,
      'is_multi_unit': multiUnit ? 'true' : 'false',
      switch (kind) {
        VoucherKind.receive => 'supplier',
        VoucherKind.issue => 'beneficiary',
        VoucherKind.transfer => 'destWarehouse',
        _ => 'party',
      }: party,
    };

    var i = 0;
    final rows = [
      for (final l in lines)
        multiUnit
            ? [
                nf(++i),
                l.itemName,
                nf(l.qty),
                l.unitName,
                l.beneficiary.isEmpty ? '—' : l.beneficiary,
                l.notes.isEmpty ? '—' : l.notes,
              ]
            : [
                nf(++i),
                l.itemCode,
                l.itemName,
                nf(l.qty),
                l.unitName,
                l.notes.isEmpty ? '—' : l.notes,
              ],
    ];

    // التوقيع الإلكتروني يُختم مرة واحدة لكل سند ويُطبع رمزه في أسفل الورقة.
    // إن لم يكن للقائد مفتاح على هذا الجهاز يُطبع السند بلا رمز كما كان.
    final token = await SignaturesRepo(db).signOnce(
      docRef: refNo,
      payload: SignaturesRepo.payloadOf(
        refNo: refNo,
        date: date,
        warehouse: warehouse,
        party: party,
        lines: [
          for (final l in lines) (item: l.itemName, unit: l.unitName, qty: l.qty),
        ],
      ),
    );

    final bytes = switch (kind) {
      VoucherKind.receive => await engine.receiveVoucher(master, rows, signatureToken: token),
      VoucherKind.issue => withReceipt
          ? await engine.issueWithReceipt(master, rows, signatureToken: token)
          : await engine.issueVoucher(master, rows, signatureToken: token),
      VoucherKind.transfer => await engine.transferVoucher(master, rows, signatureToken: token),
      VoucherKind.returnFromUnit =>
        await engine.returnVoucher(master, rows, fromUnit: true, signatureToken: token),
      VoucherKind.returnToSupplier =>
        await engine.returnVoucher(master, rows, fromUnit: false, signatureToken: token),
    };
    await MilitaryPrint.show(bytes, name: '$title $refNo');
  }

  /// يبني المحرك من هوية الجهة المحفوظة (الشعار والأسطر والتذييل).
  static Future<MilitaryPrint> engineOf(AppDatabase db, {String printedBy = ''}) async {
    final settings = SettingsRepo(db);
    final id = await settings.identity();
    final layout = await settings.printLayout();
    final lines = id.orgLines.isNotEmpty
        ? id.orgLines
        : [for (final l in layout.right.where((l) => l.show)) l.text];
    final footer = layout.footer.where((l) => l.show).map((l) => l.text).join(' — ');
    return MilitaryPrint(
      orgLines: lines.isEmpty ? const ['الجمهورية اليمنية'] : lines,
      logoBase64: id.logoBase64,
      printedBy: printedBy.isEmpty ? 'مسؤول النظام' : printedBy,
      customFooter: footer,
      approvalLabel: layout.approval.text,
      approvalVisible: layout.approval.show,
      printFont: layout.fontFamily,
    );
  }

  /// يعرض إشعار الحفظ ومعه زر طباعة مباشر.
  static void offer(
    BuildContext context, {
    required String message,
    required Future<void> Function() onPrint,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'طباعة', onPressed: () => onPrint()),
      ),
    );
  }
}
