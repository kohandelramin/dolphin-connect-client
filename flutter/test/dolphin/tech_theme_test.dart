import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/tech_theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// DD-53: the technician app's light and dark palettes; every text pair the technician views use reaches AA.
void main() {
  test('the choice follows Windows by default and maps to a brightness', () {
    expect(techBrightness(ThemeMode.system, Brightness.dark), Brightness.dark);
    expect(techBrightness(ThemeMode.system, Brightness.light), Brightness.light);
    expect(techBrightness(ThemeMode.light, Brightness.dark), Brightness.light);
    expect(techBrightness(ThemeMode.dark, Brightness.light), Brightness.dark);
    expect(themeModeLabel(ThemeMode.system), 'مثل ویندوز');
    expect(themeModeLabel(ThemeMode.light), 'روشن');
    expect(themeModeLabel(ThemeMode.dark), 'تیره');
  });

  for (final p in [DolphinTechPalette.light, DolphinTechPalette.dark]) {
    test('${p.brightness.name} palette: every text pair reaches AA', () {
      for (final (name, fg, bg) in [
        ('ink on surface', p.ink, p.surface),
        ('ink on ground', p.ink, p.ground),
        ('muted on surface', p.muted, p.surface),
        ('muted on ground', p.muted, p.ground),
        ('accent on surface', p.accent, p.surface),
        ('accent on ground', p.accent, p.ground),
        ('accent on accentSoft', p.accent, p.accentSoft),
        ('ok on surface', p.okText, p.surface),
        ('warn on surface', p.warnText, p.surface),
        ('danger on surface', p.dangerText, p.surface),
      ]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '${p.brightness.name}: $name');
      }
    });
  }

  testWidgets('DolphinTechTheme follows the app theme: dark ground in dark, light ground in light', (tester) async {
    for (final (mode, ground) in [
      (ThemeMode.dark, DolphinTechPalette.dark.ground),
      (ThemeMode.light, DolphinTechPalette.light.ground),
    ]) {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: mode,
          home: const DolphinTechTheme(child: Text('x'))));
      await tester.pumpAndSettle(); // MaterialApp animates a theme change
      expect(backgroundOf(tester, find.text('x')), ground);
    }
  });
}
