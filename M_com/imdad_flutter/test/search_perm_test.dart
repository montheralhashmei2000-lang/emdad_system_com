import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/data/db/app_database.dart';
import 'package:imdad/data/search/search_service.dart';
import 'package:imdad/domain/perm_catalog.dart';

/// صلاحيةُ كل جدولٍ في البحث العام هي صلاحيةُ صفحته بعينها.
///
/// البحث يقرأ ستة عشر جدولًا من شاشاتٍ متفرقة، فهو أوسعُ نافذةٍ على البيانات في
/// النظام: خطأٌ في سطرٍ واحدٍ من تعريفاته يكشف جدولًا كاملًا لمن لا يملكه. وقد
/// وقع: جدول الأفراد كان يُحرَس بصلاحية «الارتباطات» وصفحتُه تُحرَس بصلاحية
/// «القوة البشرية» المستقلة، فكان من يملك المالية وحدها يقرأ أسماء الأفراد
/// وأرقامهم العسكرية. فالاختبار يحرس **القاعدة** لا تلك الحالة وحدها.
void main() {
  test('صفحةٌ لها صلاحيتها الخاصة تُحرَس بها لا بصلاحيةٍ أوسع', () {
    final wrong = <String>[
      for (final t in SearchService.scanned)
        // صفحةٌ اسمها نفسه مفتاحُ صلاحية في `PermCatalog` ⇒ تلك صلاحيتها، ولا
        // يصحّ أن يُحرَس جدولها بغيرها. وصفحةٌ ليست مفتاحًا (مثل `linkFinances`)
        // تُعادَل بصلاحية أخرى في الشل، فتُقبل كما هي.
        if (PermCatalog.byKey.containsKey(t.page) && t.perm != t.page)
          '${t.table}: الصفحة ${t.page} صلاحيتها «${t.page}» والبحث يحرسها بـ«${t.perm}»',
    ];
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('كل صلاحيةٍ يذكرها البحث موجودةٌ في كتالوج الصلاحيات', () {
    final unknown = <String>[
      for (final t in SearchService.scanned)
        if (!PermCatalog.byKey.containsKey(t.perm)) '${t.table}: صلاحيةٌ مجهولة «${t.perm}»',
    ];
    // صلاحيةٌ لا وجود لها تعني `has()` يردّ false دائمًا للمستخدم العادي
    // وtrue للمدير — حجبٌ صامت أو انفتاحٌ صامت، وكلاهما خطأ.
    expect(unknown, isEmpty, reason: unknown.join('\n'));
  });

  test('من يملك المالية دون القوة البشرية لا يجد الأفراد بالبحث', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.linkPersons).insert(LinkPersonsCompanion.insert(
          id: 'p1',
          fullName: 'سالم المحسني',
          militaryNo: const Value('99887'),
          rank: const Value('رقيب'),
        ));

    final svc = SearchService(db);

    // «الارتباطات» وحدها: لا أفراد.
    final finance = await svc.search('سالم',
        access: SearchAccess(canView: (p) => p == 'linkages', scope: null));
    expect(finance.isEmpty, isTrue, reason: 'صلاحية المالية كشفت سجلات القوة البشرية');

    // «القوة البشرية»: يجدهم.
    final hr = await svc.search('سالم',
        access: SearchAccess(canView: (p) => p == 'personnel', scope: null));
    expect(hr.total, 1);
    expect(hr.byType.values.single.single.page, 'personnel');
  });
}
