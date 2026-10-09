import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/voucher_print.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';
import 'package:imdad/domain/print_forms.dart';
import 'package:imdad/domain/print_layout.dart';

/// تفريد النماذج المطبوعة بتصميمٍ لكلٍّ منها.
///
/// السؤال الذي تجيب عنه: هل لكل مطبوعةٍ في النظام مفتاحٌ في الفهرس، وهل
/// يقرأ كلُّ موضعِ طباعةٍ تخطيطَ مطبوعتِه — لا تخطيطًا عامًّا ولا
/// `PrintLayout.defaults` المثبَّت في الكود؟
/// نصُّ وسائط النداء الذي يبدأ قوسُه عند [open] — بموازنة الأقواس، فالوسيط
/// `layout:` قد يأتي بعد `doc:` الطويل ونافذةٌ بعدد حروفٍ ثابت تفوته.
String _callArgs(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final ch = src[i];
    if (ch == '(') depth++;
    if (ch == ')') {
      depth--;
      if (depth == 0) return src.substring(open, i);
    }
  }
  return src.substring(open);
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('الفهرس', () {
    test('المفاتيح فريدة والأسماء غير فارغة', () {
      final keys = <String>{};
      for (final f in PrintForms.all) {
        expect(keys.add(f.key), isTrue, reason: 'مفتاح مكرر: ${f.key}');
        expect(f.label.trim(), isNotEmpty, reason: f.key);
        expect(f.screen.trim(), isNotEmpty, reason: f.key);
        expect(f.group.trim(), isNotEmpty, reason: f.key);
      }
    });

    test('القسمان كلاهما ممثَّل، والبرقيات والارتباطات ضمن الفهرس', () {
      expect(PrintForms.all.where((f) => f.space == PrintFormSpace.supply), isNotEmpty);
      expect(PrintForms.all.where((f) => f.space == PrintFormSpace.fuel), isNotEmpty);
      // الثلاثة التي شكا منها المستخدم: البرقيات والارتباطات والمالية.
      for (final key in [
        PrintForms.cableForm,
        PrintForms.cableLog,
        PrintForms.roster,
        PrintForms.custodyClearance,
        PrintForms.financeStatement,
        PrintForms.purchaseContract,
        PrintForms.custodySheet,
        PrintForms.moneyReceipt,
      ]) {
        expect(PrintForms.has(key), isTrue, reason: key);
      }
    });

    test('كل نوع سندٍ يُحوَّل إلى مفتاحٍ معروف', () {
      for (final kind in VoucherKind.values) {
        final key = VoucherPrint.formOf(kind);
        expect(PrintForms.has(key), isTrue, reason: '$kind ⇒ $key مجهول');
      }
    });

    test('المجموعات بترتيب ظهورها بلا تكرار', () {
      final groups = PrintForms.groups;
      expect(groups, equals(groups.toSet().toList()));
      expect(groups.first, PrintForms.groupVouchers);
    });
  });

  group('قراءة التخطيط', () {
    test('بلا إفراد: المطبوعة تتبع التخطيط العام', () async {
      final repo = SettingsRepo(db);
      await repo.savePrintLayout(PrintLayout.defaults.copyWith(titleSize: 22));

      expect((await repo.printLayoutFor(PrintForms.cableLog)).titleSize, 22);
      expect((await repo.printLayoutFor('')).titleSize, 22);
      expect((await repo.printLayoutFor(null)).titleSize, 22);
    });

    test('الإفراد يعزل المطبوعة عن العام ولا يمسّ غيرها', () async {
      final repo = SettingsRepo(db);
      await repo.savePrintLayout(PrintLayout.defaults.copyWith(titleSize: 22));
      await repo.savePrintLayoutFor(
        PrintForms.cableLog,
        PrintLayout.defaults.copyWith(titleSize: 9, fontFamily: 'Cairo'),
      );

      expect((await repo.printLayoutFor(PrintForms.cableLog)).titleSize, 9);
      expect((await repo.printLayoutFor(PrintForms.cableLog)).fontFamily, 'Cairo');
      // العام وبقية المطبوعات كما كانت.
      expect((await repo.printLayout()).titleSize, 22);
      expect((await repo.printLayoutFor(PrintForms.receipt)).titleSize, 22);
      expect(await repo.customizedPrintForms(), {PrintForms.cableLog});
    });

    test('حذف الإفراد يعيدها إلى العام', () async {
      final repo = SettingsRepo(db);
      await repo.savePrintLayout(PrintLayout.defaults.copyWith(titleSize: 22));
      await repo.savePrintLayoutFor(PrintForms.roster, PrintLayout.defaults.copyWith(titleSize: 8));
      expect((await repo.printLayoutFor(PrintForms.roster)).titleSize, 8);

      await repo.clearPrintLayoutFor(PrintForms.roster);
      expect((await repo.printLayoutFor(PrintForms.roster)).titleSize, 22);
      expect(await repo.customizedPrintForms(), isEmpty);
    });

    test('مفتاحٌ مجهول (تخطيطٌ قديم) لا يُعطّل الطباعة بل يتبع العام', () async {
      final repo = SettingsRepo(db);
      await repo.savePrintLayout(PrintLayout.defaults.copyWith(titleSize: 17));
      expect((await repo.printLayoutFor('formRemovedLongAgo')).titleSize, 17);
      expect(PrintForms.labelOf('formRemovedLongAgo'), 'formRemovedLongAgo');
    });

    test('تخطيطات النماذج تُزامَن: صورةُ السند معيارُ الجهة لا تفضيلُ جهاز', () {
      expect(SettingsRepo.localOnlyKeys, isNot(contains(SettingsRepo.printFormsKey)));
      expect(SettingsRepo.localOnlyKeys, isNot(contains(SettingsRepo.printLayoutKey)));
    });
  });

  group('مواضع الطباعة', () {
    /// كل نداء `DocumentPdf.printDoc`/`share` في الشاشات يجب أن يمرّر
    /// `layout:`؛ النداء بلا تخطيط يطبع بـ`PrintLayout.defaults` — ترويسةٌ
    /// مثبَّتة في الكود لا يملك أحدٌ تعديلها. هكذا كان سجلّ البرقيات وكشف
    /// القوة البشرية وكشفا العهدة والحساب.
    test('لا نداءَ طباعةٍ بلا layout في features', () {
      final offenders = <String>[];
      for (final file in Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = file.readAsStringSync();
        for (final call in ['DocumentPdf.printDoc(', 'DocumentPdf.share(', 'DocumentPdf.build(']) {
          var at = src.indexOf(call);
          while (at >= 0) {
            if (!_callArgs(src, at + call.length - 1).contains('layout:')) {
              offenders.add('${file.path} :: $call');
            }
            at = src.indexOf(call, at + call.length);
          }
        }
      }
      expect(offenders, isEmpty, reason: 'طباعةٌ بتخطيطٍ مثبَّت:\n${offenders.join('\n')}');
    });

    /// كلُّ مفتاحٍ يُمرَّر إلى `printLayoutFor(PrintForms.x)` معرَّفٌ في الفهرس
    /// — وإلا كانت المطبوعة تقرأ مفتاحًا لا يظهر في منتقي المصمم، فلا يملك
    /// أحدٌ إفرادها بتصميم.
    test('كل مفتاح مستعمل في الكود موجودٌ في الفهرس', () {
      final used = <String>{};
      final re = RegExp(r'PrintForms\.([A-Za-z][A-Za-z0-9]*)');
      for (final dir in ['lib/features', 'lib/core/print']) {
        for (final file in Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          for (final m in re.allMatches(file.readAsStringSync())) {
            used.add(m.group(1)!);
          }
        }
      }
      // أعضاءٌ ليست مفاتيح: الدوال والقوائم والمجموعات.
      const notKeys = {'all', 'groups', 'find', 'labelOf', 'has',
        'groupVouchers', 'groupReports', 'groupFuel', 'groupLinks', 'groupCables'};
      final keys = {for (final f in PrintForms.all) f.key};
      final unknown = used.difference(notKeys).difference(keys);
      expect(unknown, isEmpty, reason: 'مفاتيح تُستعمل ولا تُعرَّف: $unknown');
      expect(used.intersection(keys), isNotEmpty);
    });
  });
}
