import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/call_status.dart';
import 'package:flutter_hbb/dolphin/panel_bridge.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  test('the field checks the ID before it asks the panel', () {
    expect(manualIdProblem(''), isNotNull);
    expect(manualIdProblem('12'), contains('درست نیست'));
    expect(manualIdProblem('123 456 789'), isNull);
  });

  test('the field asks the panel, never the PC', () {
    expect(callRequest('123456789'), '{"type":"dolphin-call","id":"123456789"}');
  });

  test('the panel answers the field with a short text', () {
    final m = parsePanelMessage({'type': 'dolphin-call-result', 'ok': false, 'text': 'این رایانه در جلسه با علی است'});
    expect([m?.type, m?.ok, m?.text], ['dolphin-call-result', false, 'این رایانه در جلسه با علی است']);
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': 'yes', 'text': 'x'}), isNull);
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': true, 'text': '  '}), isNull);
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': true, 'text': 'ا' * 500})?.text.length, kCallResultMaxLength);
  });

  test('connect carries the one-time code only when it looks like one', () {
    expect(parsePanelMessage({'type': 'dolphin-connect', 'id': '123456789', 'code': 'Ab3dE6gh'})?.code, 'Ab3dE6gh');
    expect(parsePanelMessage({'type': 'dolphin-connect', 'id': '123456789'})?.code, '');
    expect(parsePanelMessage({'type': 'dolphin-connect', 'id': '123456789', 'code': 'x y'}), isNull);
  });

  testWidgets('the line under the field shows what the panel said', (tester) async {
    await tester.pumpWidget(_app(const DolphinCallStatus(text: 'تماس باز شد', ok: true)));
    expect(find.text('تماس باز شد'), findsOneWidget);
  });

  testWidgets('no answer from the panel: the app says so and the field works again', (tester) async {
    final wait = DolphinCallWait(const Duration(seconds: 8));
    addTearDown(wait.dispose);
    await tester.pumpWidget(_app(ListenableBuilder(
      listenable: wait,
      builder: (_, __) => Column(children: [
        TextField(enabled: !wait.busy),
        if (wait.text != null) DolphinCallStatus(text: wait.text!, ok: wait.ok),
      ]),
    )));
    wait.waiting();
    await tester.pump();
    expect(find.text(kPanelChecking), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.pump(const Duration(seconds: 7));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(kPanelNoAnswer), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('an answer ends the wait before the timeout and shows as plain text', (tester) async {
    final wait = DolphinCallWait(const Duration(seconds: 8));
    addTearDown(wait.dispose);
    await tester.pumpWidget(_app(ListenableBuilder(
      listenable: wait,
      builder: (_, __) => Column(children: [
        TextField(enabled: !wait.busy),
        if (wait.text != null) DolphinCallStatus(text: wait.text!, ok: wait.ok),
      ]),
    )));
    wait.waiting();
    wait.show('<b>علی</b> https://x.y', ok: false);
    await tester.pump();
    expect(find.text('<b>علی</b> https://x.y'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text(kPanelNoAnswer), findsNothing);
  });
}
