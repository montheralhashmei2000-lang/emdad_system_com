import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/security/perm.dart';
import 'package:imdad/domain/menu_doors.dart';

/// أبواب القائمة وصلاحياتها.
///
/// **بابٌ يشير إلى نفسه يُسقط القائمة كلها.** فحصُ الصلاحية يستدعي نفسه بلا
/// نهاية فيفيض المكدّس؛ وفي نسخة الإصدار لا تظهر رسالة، بل مستطيلٌ رمادي
/// مكان الشريط الجانبي. وقع ذلك فعلًا في `supplyReports`، ولذلك هذا الملف.
void main() {
  group('سلامة الخريطة', () {
    test('لا بابَ يشير إلى نفسه', () {
      expect(selfReferencingDoors(), isEmpty,
          reason: 'تبويبةٌ تحمل اسم بابها تُدخل الفحص في تكرارٍ لا نهائي');
    });

    test('لا بابَ فارغ', () {
      for (final e in kMenuDoors.entries) {
        expect(e.value, isNotEmpty, reason: 'الباب «${e.key}» بلا تبويبات');
      }
    });

    test('كل تبويبةٍ صلاحيةٌ معروفة', () {
      for (final e in kMenuDoors.entries) {
        for (final tab in e.value) {
          // التبويبة صلاحيةٌ معرَّفة، أو بابٌ آخر بتبويباته.
          expect(Perm.labels.containsKey(tab) || kMenuDoors.containsKey(tab),
              isTrue,
              reason: 'التبويبة «$tab» في «${e.key}» بلا صلاحية معرَّفة');
        }
      }
    });

    test('لا تبويبةَ تتكرر في بابين', () {
      final seen = <String, String>{};
      for (final e in kMenuDoors.entries) {
        for (final tab in e.value) {
          expect(seen.containsKey(tab), isFalse,
              reason: '«$tab» في «${e.key}» و«${seen[tab]}» معًا');
          seen[tab] = e.key;
        }
      }
    });
  });

  group('فتح الباب', () {
    test('يُفتح لمن ملك تبويبةً واحدة', () {
      expect(menuDoorAllows('supplyMoves', (p) => p == 'issue'), isTrue);
    });

    test('يُغلق عمّن لم يملك شيئًا منه', () {
      expect(menuDoorAllows('supplyMoves', (p) => p == 'items'), isFalse);
    });

    test('بابٌ مجهول لا يُفتح', () {
      expect(menuDoorAllows('لا-شيء', (_) => true), isFalse);
    });

    test('بابٌ يشير إلى نفسه لا يتكرر إلى ما لا نهاية', () {
      // الحارس يتخطّى التبويبة التي تحمل اسم بابها، فلو دخلت الخريطة يومًا
      // لم تسقط القائمة — يُغلق الباب ولا يفيض المكدّس.
      var calls = 0;
      final ok = menuDoorAllows('supplyData', (p) {
        calls++;
        return p == 'supplyData';
      });
      expect(ok, isFalse);
      expect(calls, lessThan(20), reason: 'الفحص لم يتوقف');
    });
  });
}
