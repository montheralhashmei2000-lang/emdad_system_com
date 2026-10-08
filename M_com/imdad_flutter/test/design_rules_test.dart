import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس قواعد التصميم (CLAUDE.md): لا ألوان صريحة، ولا عروض ثابتة جديدة.
///
/// **الألوان:** كل لونٍ معرَّفٌ في `imd_tokens.dart` (السمة أو [ImdFixedColors]).
/// **العروض:** `SizedBox(width: ≥100)` الجديدة في الشاشات يُستعاض عنها بـ `ImdFit`
/// (يتقلّص مع المتاح) أو `Expanded/Flexible`. المستثنى أدناه مواضع مبرَّرة:
/// خلايا جداول الإدخال (تقيس أبعادها الذاتية فلا يصلح LayoutBuilder)، ولوحتا
/// التنقل الجانبيتان في فرع سطح المكتب (>900) فقط، وأعمدة تسميات ثابتة.
void main() {
  List<File> dartFiles() => [
        for (final e in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart') && !e.path.endsWith('.g.dart')) e,
      ];

  String rel(File f) => f.path.replaceAll(String.fromCharCode(92), '/');

  test('لا ألوان Material صريحة (Colors.white/black/red…) خارج ملف الرموز', () {
    final pattern = RegExp(r'(?<![A-Za-z])Colors\.(white|black|red|green|blue|grey|orange|amber|yellow|purple|teal|pink|cyan|indigo|brown)\b');
    final bad = <String>[];
    for (final f in dartFiles()) {
      if (rel(f).endsWith('core/ui/imd_tokens.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i]) && !lines[i].trimLeft().startsWith('//')) bad.add('${rel(f)}:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: 'استعمل context.imd أو ImdFixedColors:\n${bad.join('\n')}');
  });

  /// المواضع المبرَّرة — **سقفٌ لا يرتفع**، ويُخفَض كلما نُظّف ملف.
  ///
  /// قائمةٌ متسامحة بلا حارسٍ ثانٍ تتبوّأ: ملفٌّ نُظّف يبقى مأذونًا له، فيعود
  /// إليه العرضُ الثابت بعد حين بلا أن يَفشل شيء. فمعها اختبارٌ ثانٍ يُفشل
  /// الاستثناءَ البائت — كما يحرس `layering_test` سقفَه باختبارٍ ثانٍ.
  const allowed = {
    // خلايا جداول الإدخال/الجداول: تُقاس ذاتيًّا فلا يصلح لها LayoutBuilder.
    'lib/features/fuel/fuel_consumption_screen.dart',
    'lib/features/fuel/fuel_directories_screen.dart',
    'lib/features/fuel/fuel_plan_vs_issued_screen.dart',
    'lib/features/fuel/fuel_stocktake_screen.dart',
    'lib/features/inventory/issue_screen.dart',
    'lib/features/inventory/ration_order/ration_approve_sheet.dart',
    'lib/features/inventory/receive_screen.dart',
    'lib/features/inventory/returns_screen.dart',
    'lib/features/inventory/transfer_screen.dart',
    // لوحة التنقل الجانبية في فرع سطح المكتب فقط (>900).
    'lib/features/reports/reports_center_screen.dart',
    'lib/features/settings/settings_screen.dart',
    // عمود تسمية ثابت في صفّ مفتاح/قيمة.
    'lib/features/settings/verify_sign_screen.dart',
  };

  final widthPattern = RegExp(r'SizedBox\(\s*width:\s*\d{3,}');

  List<String> offenders() => [
        for (final f in dartFiles())
          if (rel(f).startsWith('lib/features/') && widthPattern.hasMatch(f.readAsStringSync()))
            rel(f),
      ];

  test('لا SizedBox(width ≥ 100) جديد في الشاشات خارج المواضع المبرَّرة', () {
    final bad = [
      for (final f in offenders())
        if (!allowed.contains(f)) f,
    ];
    expect(bad, isEmpty, reason: 'استعمل ImdFit(width: …) بدل SizedBox:\n${bad.join('\n')}');
  });

  test('لا حشوة فيزيائية (left/right) في واجهةٍ عربية — استعمل Directional', () {
    // الواجهة RTL: `EdgeInsets.only(left:)` يبقى على اليسار الفيزيائي، أي على
    // **نهاية** السطر لا بدايته، فتظهر الحشوة على الجانب الخطأ. والاتجاهيّة
    // (`EdgeInsetsDirectional.only(start:)`) تنعكس مع الاتجاه كما يُراد.
    //
    // ملفات الطباعة مستثناة: `pw.EdgeInsets` من حزمة pdf، وصفحتُها فيزيائية
    // بطبيعتها ولا تنعكس.
    final pattern = RegExp(r'(?<!pw\.)EdgeInsets\.only\(\s*(left|right):');
    final bad = <String>[];
    for (final f in dartFiles()) {
      if (rel(f).contains('/core/print/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i]) && !lines[i].trimLeft().startsWith('//')) {
          bad.add('${rel(f)}:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty,
        reason: 'استعمل EdgeInsetsDirectional.only(start/end:):\n${bad.join('\n')}');
  });

  test('قائمة الاستثناءات محدَّثة: ما نُظّف يُحذف منها', () {
    final now = offenders().toSet();
    final stale = [
      for (final f in allowed)
        if (!now.contains(f)) f,
    ];
    expect(stale, isEmpty,
        reason: 'هذه الملفات نظيفةٌ الآن — احذفها من allowed حتى لا تُجاز فيها عودة:\n'
            '${stale.join('\n')}');
  });
}
