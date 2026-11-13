import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/share.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  test('the share-toggle switch shows the control unless hidden (DD-34)', () {
    expect(shareControlShown(SwitchMode.available), isTrue);
    expect(shareControlShown(SwitchMode.forced), isTrue);
    expect(shareControlShown(SwitchMode.hidden), isFalse);
    expect(shareControlShown(DolphinSwitches.parse('-').mode(DolphinSwitch.shareToggle)), isTrue); // portal default
  });

  test('stopped is read like the server reads it (src/dolphin_system_core.rs)', () {
    expect(sharingStopped(SwitchMode.available, 'Y'), isTrue);
    expect(sharingStopped(SwitchMode.forced, 'Y'), isTrue);
    expect(sharingStopped(SwitchMode.hidden, 'Y'), isFalse); // no control: an old Y does not lock the PC
    expect(sharingStopped(SwitchMode.available, ''), isFalse);
    expect(shareToggleValue(false), 'Y');
    expect(shareToggleValue(true), '');
  });

  test('a press shows at once and gives way to the server after 5 s', () {
    const s = Duration(seconds: 1);
    expect(shareShownStopped(read: false), isFalse);
    expect(shareShownStopped(read: false, pending: true, sincePress: s), isTrue);
    expect(shareShownStopped(read: true, pending: true, sincePress: s), isTrue);
    expect(shareShownStopped(read: false, pending: true, sincePress: const Duration(seconds: 6)), isFalse);
  });

  testWidgets('Plan 19 C1: the «اشتراک‌گذاری» switch says what holds now; on while sharing, off when stopped',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_app(DolphinShareView(stopped: false, onToggle: () => pressed++)));
    expect(find.text(kShareRowLabel), findsOneWidget);
    expect(find.text(kShareOnHint), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('dolphin-share-toggle'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('dolphin-share-toggle')));
    expect(pressed, 1);
    // The whole row is the target.
    await tester.tap(find.text(kShareRowLabel));
    expect(pressed, 2);

    await tester.pumpWidget(_app(DolphinShareView(stopped: true, onToggle: () => pressed++)));
    expect(find.textContaining(kShareOffLabel), findsOneWidget);
    expect(find.textContaining(kShareOffHint), findsOneWidget);
    expect(tester.widget<Switch>(find.byKey(const ValueKey('dolphin-share-toggle'))).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('dolphin-share-toggle')));
    expect(pressed, 3);
  });

  testWidgets('the switch reads in light and dark', (tester) async {
    for (final b in [Brightness.light, Brightness.dark]) {
      DolphinCustomerTheme.apply(b == Brightness.dark ? DolphinThemeChoice.dark : DolphinThemeChoice.light,
          platform: Brightness.light);
      for (final stopped in [false, true]) {
        await tester.pumpWidget(_app(DolphinLight(child: DolphinShareView(stopped: stopped, onToggle: () {}))));
        expectAllTextReadable(tester);
      }
    }
    DolphinCustomerTheme.reset();
  });

  testWidgets('the strip fits the 320 px customer window', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final stopped in [false, true]) {
      await tester.pumpWidget(_app(Column(children: [DolphinShareView(stopped: stopped, onToggle: () {})])));
      expect(tester.takeException(), isNull);
    }
  });

  test('stopping says that nobody, not even Dolphin, can connect', () {
    expect(kShareOffHint, contains('هیچ کس'));
    expect(DolphinColors.dangerText, isNot(DolphinColors.aquaText));
  });
}
