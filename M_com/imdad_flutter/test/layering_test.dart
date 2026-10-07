import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// فصل الطبقات: الشاشات (`lib/features`) تستعمل المستودعات (`lib/data/repos`) ولا
/// تستعلم Drift مباشرة. ما بقي منها مثبَّتٌ هنا (سقفٌ لا يرتفع): أي استعلامٍ مباشر
/// جديد، أو ملفٌّ جديد يستعلم، يُفشل الاختبار. وحين تنقل استعلامات ملفٍّ إلى مستودع
/// **اخفض رقمه** (أو احذف سطره عند الصفر) — الاختبار يفشل إن بقي السقف أعلى من الواقع
/// حتى لا يتحوّل التحسُّن إلى مساحة لتراجعٍ لاحق.
const Map<String, int> _allowed = {
  'settings/settings_screen.dart': 3,
  'linkages/custody_sheet_editor.dart': 3,
  'linkages/link_finances.dart': 2,
  'linkages/money_receipts_tab.dart': 1,
  'daily/kitchen_log_screen.dart': 1,
  'archive/electronic_archive_screen.dart': 1,
};

void main() {
  final direct = RegExp(r'\b_?db\.(select|into|update|delete|transaction|customSelect|customStatement)\(');

  Map<String, int> measure() {
    final root = Directory('lib/features');
    final out = <String, int>{};
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final n = direct.allMatches(f.readAsStringSync()).length;
      if (n > 0) out[f.path.replaceAll('\\', '/').replaceFirst('lib/features/', '')] = n;
    }
    return out;
  }

  test('لا استعلام Drift مباشر جديد في الشاشات (السقف لا يرتفع)', () {
    final now = measure();
    final worse = <String>[
      for (final e in now.entries)
        if (e.value > (_allowed[e.key] ?? 0)) '${e.key}: ${e.value} > ${_allowed[e.key] ?? 0}',
    ];
    expect(worse, isEmpty, reason: 'انقل الاستعلام إلى مستودع في lib/data/repos بدل استدعاء Drift من الشاشة');
  });

  test('السقف محدَّث: ما نُقل إلى مستودع يُخفَض رقمه هنا', () {
    final now = measure();
    final stale = <String>[
      for (final e in _allowed.entries)
        if ((now[e.key] ?? 0) < e.value) '${e.key}: الواقع ${now[e.key] ?? 0} < السقف ${e.value}',
    ];
    expect(stale, isEmpty, reason: 'اخفض الرقم (أو احذف السطر) في _allowed');
  });
}
