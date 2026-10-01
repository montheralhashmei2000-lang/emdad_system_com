import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imdad/core/theme/app_theme.dart';

/// ثيم شريط التمرير: سميكٌ، ظاهرٌ دومًا، ومتباينٌ مع خلفيته في كل سمة —
/// داكنٌ على الفاتحة وفاتحٌ على الداكنة، من onSurface نفسه لا لونين ثابتين.
void main() {
  test('رفيعٌ ساكنًا ومتمدّدٌ عند المرور، ولا ظهور دائم', () {
    for (final theme in [AppTheme.light(), AppTheme.dark(), AppTheme.fuel()]) {
      final s = theme.scrollbarTheme;
      expect(s.thickness?.resolve({}), 6);
      expect(s.thickness?.resolve({WidgetState.hovered}), 10);
      expect(s.radius, const Radius.circular(5));
      expect(s.thumbVisibility?.resolve({}), isFalse);
    }
  });

  test('لون الإبهام داكنٌ في الفاتح وفاتحٌ في الداكن', () {
    final lightThumb = AppTheme.light().scrollbarTheme.thumbColor?.resolve({});
    final darkThumb = AppTheme.dark().scrollbarTheme.thumbColor?.resolve({});

    // الحساب من onSurface: نصٌّ داكنٌ على الفاتح ⇒ إبهامٌ داكن، والعكس.
    expect(lightThumb, isNotNull);
    expect(darkThumb, isNotNull);
    expect(ThemeData.estimateBrightnessForColor(lightThumb!), Brightness.dark);
    expect(ThemeData.estimateBrightnessForColor(darkThumb!), Brightness.light);
  });
}
