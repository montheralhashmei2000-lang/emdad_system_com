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

  test('لا SizedBox(width ≥ 100) جديد في الشاشات خارج المواضع المبرَّرة', () {
    const allowed = {
      // خلايا جداول الإدخال/الجداول: تُقاس ذاتيًّا.
      'lib/features/fuel/fuel_consumption_screen.dart',
      'lib/features/fuel/fuel_directories_screen.dart',
      'lib/features/fuel/fuel_ledger_screen.dart',
      'lib/features/fuel/fuel_plan_vs_issued_screen.dart', // كان داخل fuel_ledger_screen
      'lib/features/fuel/fuel_stocktake_screen.dart',
      'lib/features/inventory/issue_screen.dart',
      'lib/features/inventory/ration_order_screen.dart',
      'lib/features/inventory/ration_order/ration_approve_sheet.dart', // كان داخل ration_order_screen
      'lib/features/inventory/receive_screen.dart',
      'lib/features/inventory/returns_screen.dart',
      'lib/features/inventory/transfer_screen.dart',
      // لوحة التنقل الجانبية في فرع سطح المكتب فقط (>900).
      'lib/features/reports/reports_center_screen.dart',
      'lib/features/settings/settings_screen.dart',
      // عمود تسمية ثابت في صفّ مفتاح/قيمة.
      'lib/features/settings/verify_sign_screen.dart',
    };
    final pattern = RegExp(r'SizedBox\(\s*width:\s*\d{3,}');
    final bad = [
      for (final f in dartFiles())
        if (rel(f).startsWith('lib/features/') && !allowed.contains(rel(f)) && pattern.hasMatch(f.readAsStringSync())) rel(f),
    ];
    expect(bad, isEmpty, reason: 'استعمل ImdFit(width: …) بدل SizedBox:\n${bad.join('\n')}');
  });
}
