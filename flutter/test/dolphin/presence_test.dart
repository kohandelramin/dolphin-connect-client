import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/presence.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  test('the stay-in-tray switch decides before any remembered answer (ADR-0016)', () {
    for (final r in ['', 'stay', 'quit', 'junk']) {
      expect(closeAction(SwitchMode.hidden, r), CloseAction.quit, reason: r); // «پنهان»: always quits, never asks
      expect(closeAction(SwitchMode.forced, r), CloseAction.stay, reason: r); // «اجباری»: always stays
    }
    expect(closeAction(SwitchMode.available, ''), CloseAction.ask);
    expect(closeAction(SwitchMode.available, 'junk'), CloseAction.ask);
    expect(closeAction(SwitchMode.available, 'stay'), CloseAction.stay);
    expect(closeAction(SwitchMode.available, 'quit'), CloseAction.quit);
    // The portal's default is «در دسترس», so a PC that never heard from the portal asks.
    expect(closeAction(DolphinSwitches.parse('-').mode(DolphinSwitch.stayInTray), ''), CloseAction.ask);
  });

  test('only a ticked box is remembered', () {
    expect(rememberValue(CloseChoice.stay, false), '');
    expect(rememberValue(CloseChoice.quit, false), '');
    expect(rememberValue(CloseChoice.stay, true), 'stay');
    expect(rememberValue(CloseChoice.quit, true), 'quit');
    // What is stored reads back as the same action.
    expect(closeAction(SwitchMode.available, rememberValue(CloseChoice.stay, true)), CloseAction.stay);
    expect(closeAction(SwitchMode.available, rememberValue(CloseChoice.quit, true)), CloseAction.quit);
  });

  testWidgets('the question offers both choices, remembers on request and can be cancelled', (tester) async {
    (CloseChoice, bool)? got;
    var cancelled = false;
    await tester.pumpWidget(_app(DolphinCloseDialogView(
      onChoose: (c, r) => got = (c, r),
      onCancel: () => cancelled = true,
    )));
    expect(find.text(kCloseTitle), findsOneWidget);
    expect(find.text(kCloseStay), findsOneWidget);
    expect(find.text(kCloseQuit), findsOneWidget);
    expect(find.text(kCloseRemember), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('dolphin-close-quit')));
    expect(got, (CloseChoice.quit, false));

    await tester.tap(find.byKey(const ValueKey('dolphin-close-remember')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dolphin-close-stay')));
    expect(got, (CloseChoice.stay, true));

    await tester.tap(find.text(kCloseCancel));
    expect(cancelled, isTrue);
  });

  testWidgets('the question fits the small customer window', (tester) async {
    tester.view.physicalSize = const Size(320, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DolphinCloseDialogView(onChoose: (_, __) {}, onCancel: () {}),
      ),
    )));
    expect(tester.takeException(), isNull);
  });

  test('the texts are the ones ADR-0016 names', () {
    expect(kCloseStay, contains('در دسترس بماند'));
    expect(kCloseQuit, 'بستن کامل');
    expect(kCloseRemember, contains('به خاطر بسپار'));
  });
}
