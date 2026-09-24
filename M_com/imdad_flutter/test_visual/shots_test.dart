import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:imdad/features/home/home_shell.dart';

import 'shots.dart';

const _pages = String.fromEnvironment('PAGES', defaultValue: 'login,dash');
const _height = int.fromEnvironment('HEIGHT', defaultValue: 900);
const _width = int.fromEnvironment('WIDTH', defaultValue: 1280);
const _seed = bool.fromEnvironment('SEED');
// DARK=true يلتقط الشاشة نفسها بالسمة الداكنة باسم `<page>-dark.png`.
const _dark = bool.fromEnvironment('DARK');

void main() {
  setUpAll(loadAppFonts);

  for (final page in _pages.split(',')) {
    testWidgets('shot $page', (tester) async {
      final h = ShotHarness();
      await h.setUp();
      setViewport(tester, width: _width.toDouble(), height: _height.toDouble());
      if (page == 'login') {
        await tester.pumpWidget(h.app(signedIn: false, dark: _dark));
        await settle(tester);
        await capture(tester, _dark ? 'login-dark' : 'login');
      } else {
        await h.signIn(tester);
        if (_seed) await h.seed(tester);
        await tester.pumpWidget(h.app(signedIn: true, dark: _dark));
        await settle(tester, rounds: 3);
        if (page != 'dash') {
          final inner = tester.element(
              find.descendant(of: find.byType(HomeShell), matching: find.byType(Scaffold)).first);
          Provider.of<ImdNav>(inner, listen: false).go(page);
        }
        await settle(tester);
        await capture(tester, _dark ? '$page-dark' : page);
      }
      await tester.runAsync(() => h.db.close());
      addTearDown(tester.view.reset);
    });
  }
}
