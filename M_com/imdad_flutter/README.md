# نظام الإمداد والتموين — تطبيق Flutter

[![CI](https://github.com/montheralhashmei2000-lang/emdad_system_com/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/montheralhashmei2000-lang/emdad_system_com/actions/workflows/ci.yml)

تطبيق أصلي لإدارة المستودعات والإمداد يعمل **دون إنترنت** على **أندرويد** و**ويندوز**:
الأصناف والمستودعات، والاستلام والصرف والتحويل والمرتجعات، والأرصدة الافتتاحية والجرد،
والتغذية اليومية والاستحقاقات، والتقارير والطباعة الرسمية، وسجل التدقيق،
ومزامنة مباشرة بين الأجهزة على الشبكة المحلية.

هو النقل الأصلي لنسخة الويب 7.4 (`../source_web_v720`). خطة النقل وحالة كل شاشة في
[`PORTING_PLAN.md`](PORTING_PLAN.md).

---

## المتطلبات

| الأداة | الإصدار |
|---|---|
| Flutter | قناة `stable`، ‏3.44 فأحدث (Dart 3.4 فأحدث) |
| أندرويد | Android SDK، والجهاز بإصدار API 23 فأعلى (يتطلبه ماسح الباركود) |
| ويندوز | Visual Studio 2022 مع حزمة «Desktop development with C++» |
| الاختبارات على لينكس | مكتبة SQLite (`sudo apt-get install libsqlite3-dev`) |

## التهيئة أول مرة

```bash
cd M_com/imdad_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # ⚠ إلزامي — توليد كود Drift
```

> **⚠ خطوة `build_runner` إلزامية، لا اختيارية.** ملفات `*.g.dart` (قاعدة البيانات، ونحو
> 52 ألف سطر) **لا تُرفع إلى المستودع**، فبدونها لا يُبنى المشروع أصلًا: يظهر في المحلل
> مئات الأخطاء من نوع «Undefined class» و«Target of URI doesn't exist»، ويفشل `flutter run`
> و`flutter test` و`flutter build`.
>
> شغّلها:
> - بعد أول `git clone` أو `git pull` يغيّر ملفات الجداول؛
> - **بعد أي تعديل** على الجداول في `lib/data/db/` (`app_database.dart` أو `linkage_tables.dart` أو
>   `archive_tables.dart` أو `cable_tables.dart`) — إضافة جدول أو عمود؛
> - بعد `flutter clean`.
>
> تستغرق نحو دقيقة إلى دقيقتين. وفي GitHub Actions تُشغَّل قبل التحليل والاختبارات.

على ويندوز يؤدي السكربت `tool\setup.ps1` الخطوات كلها، ومعها التحليل والاختبارات:

```powershell
powershell -ExecutionPolicy Bypass -File tool\setup.ps1 -FlutterHome D:\flutter
```

## التشغيل

```bash
flutter run -d windows        # سطح المكتب
flutter run -d <معرّف-الجهاز>  # أندرويد (flutter devices لعرض الأجهزة)
```

أول تشغيل على جهاز جديد يعرض **تفعيل الجهاز** (انظر «مفتاح المالك» أدناه)، ثم **تهيئة
حساب المدير الأول**.

## الفحوص

```bash
flutter analyze   # يجب أن يكون بلا أي ملاحظة
flutter test      # كل الاختبارات في test/
```

الفحصان نفساهما يعملان تلقائيًا في GitHub Actions مع كل دفع يمس هذا المجلد
(`.github/workflows/ci.yml` في جذر المستودع) عند الدفع إلى `main` وعند أي طلب دمج إليه:
`pub get` ← `build_runner` ← `analyze` ← `test`.

أداة لقطات الشاشات للمقارنة بنسخة الويب:

```bash
flutter test test_visual/shots_test.dart --dart-define=PAGES=dash,items   # ⇐ build/shots/*.png
```

## البناء للتوزيع

### أندرويد

التوقيع يُقرأ من `android/key.properties`، **وهو خارج المستودع**:

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=../../../imdad_keystore/imdad-release.p12
```

```bash
flutter build apk --release        # ⇐ build/app/outputs/flutter-apk/app-release.apk
```

### ويندوز

```bash
flutter build windows --release    # ⇐ build/windows/x64/runner/Release/
```

انسخ مجلد `Release` كاملًا: الملف التنفيذي وحده لا يعمل بدون المكتبات المجاورة له.

### بناء الإصدارين معًا (مُوصى به)

```powershell
powershell -ExecutionPolicy Bypass -File tooluild_release.ps1
```

يشغّل أولًا `dart run tool/check_release.dart` ويتوقف إن كان مفتاح المالك فارغًا أو
`android/key.properties` غائبًا، ثم يبني ويندوز و`apk` بوضع release. أي خطوة تفشل توقف
السكربت بنفس رمز خروجها.

> **توقيع الإصدار على أندرويد:** `flutter build apk --release` (و`appbundle`) **يفشل** برسالة
> `release build requires android/key.properties with signing config` إن غاب
> `android/key.properties` أو نقصت مفاتيحه (`keyAlias` و`keyPassword` و`storeFile` و`storePassword`).
> لا يُوقَّع الإصدار بمفتاح التصحيح أبدًا. بناء `debug` لا يتأثر.

### رقم الإصدار

يُضبط في `pubspec.yaml` (`version: 8.0.0+800`). الجزء بعد `+` هو `versionCode` في
أندرويد، ويجب أن **يزيد** مع كل إصدار، وإلا رفض الجهاز التحديث فوق النسخة المثبتة.

## مفتاح المالك وتفعيل الأجهزة

كل جهاز جديد يحتاج رمز تفعيل يوقّعه **المفتاح الخاص للمالك**. المفتاح العام المقابل
مضمَّن في `lib/core/security/owner_key.dart`.

```bash
dart run tool/make_owner_key.dart   # مرة واحدة: يطبع المفتاح العام ويحفظ الخاص خارج المستودع
```

- لا تضع المفتاح الخاص في المستودع أبدًا: من يملكه يستطيع تفعيل أي جهاز.
- إن ترك `publicKey` فارغًا عمل التطبيق في **وضع التطوير** بلا تفعيل. لا توزّع نسخة
  بهذا الوضع.

## بنية الكود

```
lib/
├── core/       الأمن (المصادقة، PBKDF2، التفعيل، التوقيع)، الطباعة، مكوّنات الواجهة، السمة
├── data/
│   ├── db/         قاعدة Drift (SQLite، مشفّرة بـ SQLCipher على أندرويد) والترحيلات
│   ├── repos/      الوصول للبيانات وقواعد الحفظ (الحركات، المستندات، الجرد، التقارير…)
│   ├── sync/       المزامنة المحلية بين الأجهزة وتتبّع التغييرات
│   └── migration/  الاستيراد من الويب وExcel، والتصدير والنسخ الاحتياطي المشفّر
├── domain/     قواعد عمل بلا واجهة ولا قاعدة: دفتر الأرصدة، القوة، الاستحقاقات، قواعد الصرف…
└── features/   الشاشات، مجلد لكل قسم في القائمة
```

**قاعدة عامة:** منطق الحفظ والتحقق يُكتب في `data/repos` أو `domain`، والشاشة تستدعيه
ولا تكرره. ما في هذين المجلدين يُختبر في `test/` بلا بناء واجهة.

### مفاهيم يجب معرفتها قبل التعديل

- **الأرصدة**: مصدرها الوحيد دفتر الحركات، أي الأرصدة الافتتاحية مع الاستلام والصرف
  والتحويل والمرتجعات والتسويات، ولكل مستودع رصيده (`MovementsRepo.balances`).
  عمود `items.qty` قديم، باقٍ للتوافق مع الاستيراد فقط، ولا يُقرأ كرصيد.
- **ترقيم السندات**: `و-K7QX-000001` = البادئة، ثم رمز الجهاز، ثم تسلسل الجهاز
  (`DocNumbering`). العدّاد في جدول محلي `doc_counters` لا تشمله المزامنة.
- **المزامنة**: مشغّلات SQLite تسجّل كل إدراج وتعديل وحذف في `sync_marks`، والدمج
  «آخر كاتب يفوز». تفاصيل التهيئة الميدانية في [`SYNC_SETUP.md`](SYNC_SETUP.md).
- **كلمات المرور**: PBKDF2-HMAC-SHA256 بـ 310,000 دورة، وعدد الدورات محفوظ مع كل
  حساب. الحسابات الأقدم (45,000 دورة) تُعاد تجزئتها تلقائيًا عند أول دخول ناجح.
- **تجميد الجرد**: أمر جرد مجمِّد يمنع أي حركة على مستودعه حتى اعتماده أو إلغائه.
