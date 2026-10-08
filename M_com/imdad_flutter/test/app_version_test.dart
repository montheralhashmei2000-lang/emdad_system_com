import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/features/settings/settings_screen.dart' show kAppVersion;

/// رقمُ الإصدار واحدٌ في موضعين.
///
/// كان `pubspec.yaml` على `8.0.1+801` ونصُّ «عن النظام» على «٧٫٤٫٠» — فما يراه
/// المستخدم وما يُكتب في فحص السلامة إصدارٌ قديمٌ بثلاث إصداراتٍ كاملة، ولا
/// شيء يُفشل ذلك. ترقيةُ `pubspec` وحدها تُفشل هذا الاختبار حتى يُحدَّث النصّ.
void main() {
  test('نصّ «عن النظام» يطابق إصدار pubspec', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'), orElse: () => '');
    expect(line, isNotEmpty, reason: 'لا سطر version في pubspec.yaml');

    // `8.0.1+801` ⇒ `8.0.1`
    final version = line.split(':')[1].trim().split('+').first;
    expect(kAppVersion, version,
        reason: 'حدّث kAppVersion في settings_screen.dart ليطابق pubspec');
  });
}
