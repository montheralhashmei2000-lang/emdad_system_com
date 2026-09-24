import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/domain/document_edit.dart';

void main() {
  group('تعديل المستندات المحفوظة', () {
    test('سند توريد معتمد: زيادة الكمية تضيف الفرق فقط', () {
      const ctx = DocumentContext(type: DocumentType.receipt, status: 'COMPLETED');
      final d = DocumentEdit.delta(
        context: ctx,
        before: const [DocumentLine(itemId: 'rice', baseQty: 80)],
        after: const [DocumentLine(itemId: 'rice', baseQty: 120)],
      );
      expect(d, {'rice': 40});
    });

    test('سند صرف معتمد: زيادة الكمية تخصم الفرق', () {
      const ctx = DocumentContext(type: DocumentType.issue, status: 'COMPLETED');
      final d = DocumentEdit.delta(
        context: ctx,
        before: const [DocumentLine(itemId: 'rice', baseQty: 10)],
        after: const [DocumentLine(itemId: 'rice', baseQty: 30)],
      );
      expect(d, {'rice': -20});
    });

    test('المسودة بلا أثر على الأرصدة', () {
      const ctx = DocumentContext(type: DocumentType.receipt, status: 'DRAFT');
      final d = DocumentEdit.delta(
        context: ctx,
        before: const [DocumentLine(itemId: 'rice', baseQty: 10)],
        after: const [DocumentLine(itemId: 'rice', baseQty: 900)],
      );
      expect(d, isEmpty);
    });

    test('إلغاء مرتجع صالح يعكس أثره', () {
      const ctx = DocumentContext(type: DocumentType.returnDoc, status: 'COMPLETED');
      final c = DocumentEdit.cancellation(
        context: ctx,
        lines: const [DocumentLine(itemId: 'rice', baseQty: 5)],
      );
      expect(c, {'rice': -5});
    });

    test('مرتجع تالف لا يؤثر على الرصيد', () {
      const ctx = DocumentContext(
        type: DocumentType.returnDoc,
        status: 'COMPLETED',
        condition: 'تالفة',
      );
      expect(ctx.sign, 0);
      expect(
        DocumentEdit.cancellation(context: ctx, lines: const [DocumentLine(itemId: 'rice', baseQty: 5)]),
        isEmpty,
      );
    });

    test('التحويل يُعدَّل وهو قيد الاستلام فقط وبلا أثر على الإجمالي', () {
      const pending = DocumentContext(type: DocumentType.transfer, status: 'PENDING');
      const received = DocumentContext(type: DocumentType.transfer, status: 'RECEIVED');
      expect(pending.editable, isTrue);
      expect(received.editable, isFalse);
      expect(
        DocumentEdit.delta(
          context: pending,
          before: const [DocumentLine(itemId: 'rice', baseQty: 15)],
          after: const [DocumentLine(itemId: 'rice', baseQty: 25)],
        ),
        isEmpty,
      );
    });

    test('حذف صنف وإضافة آخر يظهران في الفرق', () {
      const ctx = DocumentContext(type: DocumentType.receipt, status: 'COMPLETED');
      final d = DocumentEdit.delta(
        context: ctx,
        before: const [DocumentLine(itemId: 'rice', baseQty: 40)],
        after: const [DocumentLine(itemId: 'oil', baseQty: 20)],
      );
      expect(d, {'rice': -40, 'oil': 20});
    });

    test('منع التعديل الذي يجعل الرصيد سالبًا', () {
      final bad = DocumentEdit.check(
        delta: const {'rice': -150},
        availableBaseQty: const {'rice': 100},
      );
      expect(bad.ok, isFalse);
      expect(bad.available, 100);

      final good = DocumentEdit.check(
        delta: const {'rice': -80},
        availableBaseQty: const {'rice': 100},
      );
      expect(good.ok, isTrue);
    });
  });
}
