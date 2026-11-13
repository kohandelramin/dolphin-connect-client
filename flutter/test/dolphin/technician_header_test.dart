import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/call_status.dart';
import 'package:flutter_hbb/dolphin/tech_theme.dart';
import 'package:flutter_hbb/dolphin/technician_header.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

/// The app as the technician sees it with the light theme («روشن»).
Widget lightApp(Widget child) => MaterialApp(
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.light,
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

// AUI-2: the technician's own ID was white on a white header on a dark Windows. DD-53: the header follows the
// technician's theme choice; in both, the ID and the field read at AA.
void main() {
  Future<void> pumpHeader(WidgetTester tester, Widget Function(Widget) app,
      {ValueChanged<ThemeMode>? onThemeMode, ThemeMode mode = ThemeMode.system}) async {
    tester.view.physicalSize = const Size(2400, 600); // test font glyphs are wide
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final manual = TextEditingController(text: '123 456 789');
    final call = DolphinCallWait(const Duration(seconds: 8));
    addTearDown(call.dispose);
    addTearDown(manual.dispose);
    await tester.pumpWidget(app(DolphinTechnicianHeader(
        myId: '287654321',
        manual: manual,
        call: call,
        onConnect: () {},
        themeMode: mode,
        onThemeMode: onThemeMode)));
  }

  for (final (name, app, palette) in [
    ('dark', darkApp, DolphinTechPalette.dark),
    ('light', lightApp, DolphinTechPalette.light),
  ]) {
    testWidgets('the technician header in the $name theme: ID and field text read at AA', (tester) async {
      await pumpHeader(tester, app);
      // SelectableText draws through an EditableText, which find.text does not match.
      final id = find.descendant(of: find.byType(SelectableText), matching: find.byType(EditableText));
      expect(id, findsOneWidget);
      final idText = tester.widget<EditableText>(id);
      expect(idText.controller.text, '287 654 321');
      expect(idText.style.color, palette.ink);
      expect(backgroundOf(tester, id), palette.surface);
      expect(contrast(idText.style.color!, backgroundOf(tester, id)), greaterThanOrEqualTo(4.5));
      expectAllTextReadable(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(contrast(field.style.color!, palette.surface), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('«ظاهر» offers follow Windows, light and dark, and reports the choice', (tester) async {
    ThemeMode? picked;
    await pumpHeader(tester, lightApp, onThemeMode: (m) => picked = m, mode: ThemeMode.system);
    expect(find.byTooltip('ظاهر: مثل ویندوز'), findsOneWidget);
    await tester.tap(find.byType(DolphinThemeSwitch));
    await tester.pumpAndSettle();
    expect(find.text('مثل ویندوز'), findsOneWidget);
    expect(find.text('روشن'), findsOneWidget);
    expectAllTextReadable(tester);
    await tester.tap(find.text('تیره'));
    await tester.pumpAndSettle();
    expect(picked, ThemeMode.dark);
  });

  testWidgets('no switch without a handler', (tester) async {
    await pumpHeader(tester, lightApp);
    expect(find.byType(DolphinThemeSwitch), findsNothing);
  });
}
