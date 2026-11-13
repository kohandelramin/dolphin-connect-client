import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/share.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('the strip says what holds now and offers the other action', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(_app(DolphinShareView(stopped: false, onToggle: () => pressed++)));
    expect(find.text(kShareOnLabel), findsOneWidget);
    expect(find.text(kShareStop), findsOneWidget);
    expect(find.text(kShareStart), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dolphin-share-toggle')));
    expect(pressed, 1);

    await tester.pumpWidget(_app(DolphinShareView(stopped: true, onToggle: () => pressed++)));
    expect(find.text(kShareOffLabel), findsOneWidget);
    expect(find.text(kShareOffHint), findsOneWidget);
    expect(find.text(kShareStart), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dolphin-share-toggle')));
    expect(pressed, 2);
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
