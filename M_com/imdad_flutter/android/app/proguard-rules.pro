# قواعد R8 لنسخة الإصدار.
#
# التقليص كان يعمل أصلًا بإعداد افتراضي من إضافة Flutter؛ هذا الملف يجعله صريحًا
# ويحمي ما يُستدعى من الشيفرة الأصلية (JNI) أو بالانعكاس فلا يُحذف ولا يُعاد تسميته.

# Tesseract4Android (قراءة الفواتير OCR): الشيفرة الأصلية (libtesseract / libleptonica)
# تبحث عن هذه الأصناف وحقولها بأسمائها عبر JNI.
-keep class com.googlecode.tesseract.android.** { *; }
-keep class com.googlecode.leptonica.android.** { *; }
-keep class cz.adaptech.tesseract4android.** { *; }
-keep class io.paratoner.flutter_tesseract_ocr.** { *; }

# أي دالة native في أي صنف: اسمها مربوط باسم الدالة في المكتبة الأصلية.
-keepclasseswithmembernames class * {
    native <methods>;
}

# مكتبات اختيارية تُشير إليها تبعيات أخرى ولا تلزم وقت التشغيل.
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
