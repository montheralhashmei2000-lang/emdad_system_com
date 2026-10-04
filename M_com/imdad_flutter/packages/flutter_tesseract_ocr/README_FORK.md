# flutter_tesseract_ocr — نسخة محلية معدَّلة

أصلها `flutter_tesseract_ocr 0.4.31` (BSD). عُدِّل ملف واحد فقط: `android/build.gradle`.

## لماذا؟

الحزمة الأصلية لا تُبنى مع Gradle 9 / AGP 9 (المستعملَين في هذا المشروع):

1. `buildscript { repositories { jcenter() } }` — `jcenter()` حُذفت من Gradle 9، فيفشل تقييم المشروع:
   `Could not find method jcenter()`.
2. `classpath 'com.android.tools.build:gradle:7.1.2'` — يفرض AGP قديمًا داخل الإضافة؛
   فتفشل إضافة `kotlin-android` (التي يطبّقها Flutter) بـ«requires one of the Android Gradle plugins».
3. `compileSdkVersion` / `minSdkVersion` / `lintOptions` — صيغ DSL القديم.

## ما تغيّر

- حُذف `buildscript` و`rootProject.allprojects` (الإضافة تستعمل AGP المضيف).
- `compileSdk` و`minSdk` و`lint` بالصيغة الجديدة.
- تبعية Tesseract4Android: `api files('libs/tesseract4android-release.aar')` بدل `flatDir` + `name:/ext:`.

**لا تغيير في كود Dart ولا Java**: واجهة `FlutterTesseractOcr.extractHocr(...)` كما هي، فمنطق قراءة الفواتير لم يُمسّ.

## لماذا ليست `tesseract_ocr` (arrrrny) 0.5.0؟

جُرّبت فتبيّن:
- ملف `android/build.gradle` فيها يحتوي `jcenter()` نفسه (الفشل ذاته).
- واجهة Dart لا تكشف hOCR (`extractText` فقط) ولا تمرّر `psm` ولا `preserve_interword_spaces`؛ وكود Java يثبّت `PSM_AUTO`.
  بينما قراءة الفواتير تعتمد على مواضع الكلمات من hOCR (`parseHocr`) وعلى `psm=4`.

## الصيانة

عند صدور إصدار أعلى من الحزمة الأصلية يصلح مع Gradle 9، يُستبدل هذا المجلد بالتبعية العادية في `pubspec.yaml`.
