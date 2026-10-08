import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/print/print_format.dart';
import 'package:imdad/core/ui/imd_format.dart';
import 'package:imdad/core/ui/imd_numbers.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/repos/settings_repo.dart';

/// تنسيق الأرقام إعدادٌ واحد تتبعه الشاشات والمطبوعات.
///
/// كانت الصورة مثبَّتةً في موضعين لا يعرف أحدهما الآخر: `nf()` هنديةً بفاصلةٍ
/// ونقطة، و`printNum()/printMoney()` لاتينيةً بـ`intl`. فمن أراد تغيير خانات
/// المبالغ أو فاصل الآلاف لم يجد مكانًا يغيّره منه.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => ImdNumbers.apply(const ImdNumberPrefs()));

  group('الافتراضات لم تتغيّر', () {
    test('الشاشات: هنديةٌ بفاصلةٍ ونقطة وبلا أصفار زائدة', () {
      expect(nf(1234567), '١,٢٣٤,٥٦٧');
      expect(nf(12.5), '١٢.٥');
      expect(nf(2.500), '٢.٥', reason: 'الأصفار الزائدة تُقصّ');
      expect(nf(0), '٠');
      expect(nf(null), '٠');
    });

    test('المطبوعات: لاتينيةٌ كما في ملفات Excel المعتمدة', () {
      expect(printNum(2200), '2,200');
      expect(printNum(12.5), '12.5');
      expect(printMoney(30000), '30,000.00');
      expect(printDate('2026-05-15'), '15-05-2026 م');
    });

    test('السالب تسبقه علامة اتجاه فلا تقفز شرطته', () {
      expect(nf(-5), startsWith('؜-'));
      expect(nf(-5), endsWith('٥'));
    });
  });

  group('صورة الأرقام تتبع الإعداد', () {
    test('شاشاتٌ لاتينية', () {
      ImdNumbers.apply(const ImdNumberPrefs(uiDigits: ImdDigits.latin));
      expect(nf(1234.5), '1,234.5');
      expect(arDigits('2026-10-09'), '2026-10-09');
    });

    test('مطبوعاتٌ هندية', () {
      ImdNumbers.apply(const ImdNumberPrefs(printDigits: ImdDigits.arabic));
      expect(printNum(2200), '٢,٢٠٠');
      expect(printDate('2026-05-15'), '١٥-٠٥-٢٠٢٦ م');
    });

    test('التواريخ تتبع صورة الشاشات', () {
      expect(arDigits('2026-10-09'), '٢٠٢٦-١٠-٠٩');
    });
  });

  group('الفواصل والخانات', () {
    test('فاصل الآلاف والعشريّ', () {
      ImdNumbers.apply(const ImdNumberPrefs(thousands: ' ', decimal: '٫'));
      expect(nf(1234.5), '١ ٢٣٤٫٥');
      ImdNumbers.apply(const ImdNumberPrefs(thousands: ''));
      expect(nf(1234567), '١٢٣٤٥٦٧');
    });

    test('خانات الكميات تُقصّ أصفارها، وخانات المبالغ ثابتة', () {
      ImdNumbers.apply(const ImdNumberPrefs(qtyDecimals: 1, moneyDecimals: 3));
      expect(nf(2.567), '٢.٦', reason: 'تُقرَّب إلى خانةٍ واحدة');
      expect(nfMoney(120), '١٢٠.٠٠٠', reason: 'المبلغ يُدقَّق بخاناته فلا تُقصّ');
      ImdNumbers.apply(const ImdNumberPrefs(moneyDecimals: 0));
      expect(printMoney(30000), '30,000');
    });

    test('بلا خاناتٍ عشرية للكميات', () {
      ImdNumbers.apply(const ImdNumberPrefs(qtyDecimals: 0));
      expect(nf(2.6), '٣');
    });
  });

  group('القراءة من القاعدة', () {
    test('يُحفظ ويُقرأ ويسري على الشاشات والمطبوعات معًا', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = SettingsRepo(db);

      expect((await repo.numbers()), const ImdNumberPrefs(),
          reason: 'بلا صفٍّ محفوظ: الافتراضات');

      await repo.saveNumbers(const ImdNumberPrefs(
        uiDigits: ImdDigits.latin,
        printDigits: ImdDigits.arabic,
        moneyDecimals: 3,
      ));
      // `saveNumbers` تُفعّله فورًا فلا يُحفظ شيءٌ ويُعرض غيره.
      expect(nf(10), '10');
      expect(printMoney(10), '١٠.٠٠٠');

      ImdNumbers.apply(const ImdNumberPrefs());
      await repo.loadNumbers();
      expect(nf(10), '10', reason: 'القراءة من القاعدة تُعيد ما حُفظ');
    });

    test('صفٌّ تالفٌ لا يكسر كل رقمٍ في النظام', () async {
      final bad = ImdNumberPrefs.fromMap(const {
        'uiDigits': 'hieroglyph',
        'thousands': '☠',
        'decimal': '☠',
        'qtyDecimals': 99,
        'moneyDecimals': -3,
      });
      expect(bad, const ImdNumberPrefs(), reason: 'يعود بالافتراضات كلّها');
    });

    test('الصفّ يدور كاملًا بلا فقد', () {
      const p = ImdNumberPrefs(
        uiDigits: ImdDigits.latin,
        printDigits: ImdDigits.arabic,
        thousands: ' ',
        decimal: '٫',
        qtyDecimals: 1,
        moneyDecimals: 3,
      );
      expect(ImdNumberPrefs.fromMap(p.toMap()), p);
    });
  });
}
