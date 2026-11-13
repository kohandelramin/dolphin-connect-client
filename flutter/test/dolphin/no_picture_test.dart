import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/no_picture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// DD-16: the lock-screen / no-picture help.
void main() {
  test('the lines: why, then Ctrl+Alt+Del or ask the customer, and the not-installed note', () {
    expect(noPictureLines(canCtrlAltDel: true), [kNoPictureWhy, kNoPictureCad]);
    expect(noPictureLines(canCtrlAltDel: false), [kNoPictureWhy, kNoPictureAsk]);
    expect(noPictureLines(canCtrlAltDel: false, installed: false), [kNoPictureWhy, kNoPictureAsk, kNoPictureNotInstalled]);
    expect(noPictureLines(canCtrlAltDel: true, installed: true), [kNoPictureWhy, kNoPictureCad]);
  });

  Widget dialog(Widget Function(Widget) app, Widget content) =>
      app(Center(child: AlertDialog(content: SizedBox(width: 420, child: content))));

  testWidgets('the wait shows upstream\'s text and «قطع», then the help after the delay', (tester) async {
    var cad = 0, closed = 0;
    await tester.pumpWidget(dialog(
        lightApp,
        DolphinWaitingForPicture(
            waiting: const Text('وصل شد؛ در انتظار تصویر…'),
            after: const Duration(seconds: 8),
            canCtrlAltDel: true,
            onCtrlAltDel: () => cad++,
            onDisconnect: () => closed++)));
    expect(find.text('وصل شد؛ در انتظار تصویر…'), findsOneWidget);
    expect(find.text(kNoPictureTitle), findsNothing);
    await tester.tap(find.text(kNoPictureDisconnect));
    expect(closed, 1);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text(kNoPictureTitle), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(kNoPictureTitle), findsOneWidget);
    expect(find.text(kNoPictureCad), findsOneWidget);
    await tester.tap(find.text(kNoPictureSendCad));
    expect(cad, 1);
    // «صبر می‌کنم»: back to the plain wait, the help again after another delay.
    await tester.tap(find.text(kNoPictureWait));
    await tester.pump();
    expect(find.text(kNoPictureTitle), findsNothing);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text(kNoPictureTitle), findsOneWidget);
    await tester.tap(find.text(kNoPictureDisconnect));
    expect(closed, 2);
  });

  testWidgets('no Ctrl+Alt+Del button when the PC cannot take it; the not-installed note', (tester) async {
    await tester.pumpWidget(dialog(
        lightApp,
        DolphinNoPictureHelp(
            canCtrlAltDel: false, installed: false, onCtrlAltDel: () {}, onWait: () {}, onDisconnect: () {})));
    expect(find.text(kNoPictureSendCad), findsNothing);
    expect(find.text(kNoPictureAsk), findsOneWidget);
    expect(find.text(kNoPictureNotInstalled), findsOneWidget);
  });

  for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
    testWidgets('the help in a dialog, $name theme: every text reaches AA', (tester) async {
      await tester.pumpWidget(dialog(
          app,
          DolphinNoPictureHelp(
              canCtrlAltDel: true, installed: false, onCtrlAltDel: () {}, onWait: () {}, onDisconnect: () {})));
      await tester.pumpAndSettle();
      expectAllTextReadable(tester);
    });
  }
}
