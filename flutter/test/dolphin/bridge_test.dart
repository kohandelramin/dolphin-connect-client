import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/call_status.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
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

  test('the panel answer may carry the id of the call it answers', () {
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': true, 'text': 'x', 'id': '123456789'})?.id, '123456789');
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': true, 'text': 'x'})?.id, '');
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': true, 'text': 'x', 'id': '<b>'}), isNull);
    expect(parsePanelMessage({'type': 'dolphin-call-result', 'ok': true, 'text': 'x', 'id': 5}), isNull);
  });

  test('a result for another call is ignored; one without an id is accepted', () {
    final w = DolphinCallWait(const Duration(seconds: 30));
    addTearDown(w.dispose);
    w.waiting(id: '222222222');
    expect(w.answer('late, for A', ok: true, id: '111111111'), isFalse);
    expect(w.busy, isTrue);
    expect(w.text, kPanelChecking);
    expect(w.answer('for B', ok: true, id: '222222222'), isTrue);
    expect(w.text, 'for B');
    w.waiting(id: '333333333');
    expect(w.answer('older portal', ok: false), isTrue);
    expect(w.text, 'older portal');
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

  test('the code is shown and handed over only for a PC linked to a code-mode organization', () {
    expect(dolphinCode(approveMode: 'password', showCode: 'Y', password: 'Ab3dE6gh', inSession: false), 'Ab3dE6gh');
    expect(dolphinCode(approveMode: 'click', showCode: 'Y', password: 'Ab3dE6gh', inSession: false), '');
    expect(dolphinCode(approveMode: 'password', showCode: 'N', password: 'Ab3dE6gh', inSession: false), ''); // unlinked, or click
    expect(dolphinCode(approveMode: 'password', showCode: '', password: 'Ab3dE6gh', inSession: false), ''); // never heard from the portal
    expect(dolphinCode(approveMode: 'password', showCode: 'Y', password: '-', inSession: false), '');
  });

  test('only the portal page is answered', () {
    const portal = 'https://support.dolphindev.ir';
    expect(isPortalPage(portal, portal), isTrue);
    expect(isPortalPage('$portal/', portal), isTrue);
    expect(isPortalPage('$portal/staff/computers', portal), isTrue);
    expect(isPortalPage('$portal?a=1', portal), isTrue);
    expect(isPortalPage('$portal#x', portal), isTrue);
    expect(isPortalPage('', portal), isFalse);
    expect(isPortalPage('about:blank', portal), isFalse);
    expect(isPortalPage('$portal.evil.example', portal), isFalse);
    expect(isPortalPage('$portal.evil.example/', portal), isFalse);
    expect(isPortalPage('https://support.dolphindev.ir@evil.example/', portal), isFalse);
    expect(isPortalPage('http://support.dolphindev.ir/', portal), isFalse);
    expect(isPortalPage('https://evil.example/', portal), isFalse);
    expect(isPortalPage('https://evil.example/https://support.dolphindev.ir/', portal), isFalse);
  });

  test('the connection count from the server is the session signal', () {
    expect(connectedCount('{"status_num":1,"video_conn_count":2,"id":"1"}'), 2);
    expect(connectedCount('{"video_conn_count":0}'), 0);
    expect(connectedCount('{"status_num":1}'), 0); // missing field
    expect(connectedCount('{"video_conn_count":"2"}'), 0); // wrong type
    expect(connectedCount('{"video_conn_count":-1}'), 0);
    expect(connectedCount('not json'), 0);
    expect(connectedCount(''), 0);
    expect(connectedCount('[1,2]'), 0);
  });

  test('no code is shown or handed over while a technician is connected', () {
    expect(dolphinCode(approveMode: 'password', showCode: 'Y', password: 'Ab3dE6gh', inSession: true), '');
    expect(dolphinCode(approveMode: 'password', showCode: 'Y', password: 'Zz9yX8wv', inSession: false), 'Zz9yX8wv');
    expect(customerReply(const PanelMessage('dolphin-code-request'), '123456789', ''), isNull);
  });

  // Final review: until the first read the count is unknown, and unknown hides the code (a session accepted during the
  // update screen is live when home opens).
  test('an unknown session count hides the code', () {
    expect(codeHiddenFor(null), isTrue);
    expect(codeHiddenFor(0), isFalse);
    expect(codeHiddenFor(1), isTrue);
  });

  testWidgets('a late answer after the timeout changes nothing', (tester) async {
    final wait = DolphinCallWait(const Duration(seconds: 8));
    addTearDown(wait.dispose);
    wait.waiting();
    await tester.pump(const Duration(seconds: 9));
    expect(wait.text, kPanelNoAnswer);
    expect(wait.answer('تماس باز شد', ok: true), isFalse);
    expect(wait.text, kPanelNoAnswer);
    expect(wait.ok, isFalse);
    wait.waiting();
    expect(wait.answer('تماس باز شد', ok: true), isTrue);
    expect(wait.text, 'تماس باز شد');
  });

  test('a failed send is undone only for its own call', () {
    final wait = DolphinCallWait(const Duration(seconds: 8));
    addTearDown(wait.dispose);
    final first = wait.waiting();
    expect(wait.busy, isTrue);
    expect(wait.isCurrent(first), isTrue);
    wait.show('x', ok: true);
    final second = wait.waiting();
    expect(wait.isCurrent(first), isFalse);
    expect(wait.isCurrent(second), isTrue);
  });

  test('the customer app hands its code only when the page asks, and only a real one', () {
    expect(parsePanelMessage({'type': 'dolphin-code-request'})?.type, 'dolphin-code-request');
    expect(customerReply(const PanelMessage('dolphin-code-request'), '123456789', 'Ab3dE6gh'),
        '{"type":"dolphin-code","code":"Ab3dE6gh"}');
    expect(customerReply(const PanelMessage('dolphin-code-request'), '123456789', ''), isNull);
    expect(customerReply(const PanelMessage('dolphin-hello'), '123456789', 'Ab3dE6gh'), '{"type":"dolphin-id","id":"123456789"}');
    expect(customerReply(const PanelMessage('dolphin-connect', '987654321', 'Ab3dE6gh'), '123456789', 'Ab3dE6gh'), isNull);
  });

  testWidgets('the customer window shows the code with copy in code mode only', (tester) async {
    var copied = false;
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.ready,
        onCopy: () {},
        code: 'Ab3dE6gh',
        onCopyCode: () => copied = true,
        phone: '',
        siteLabel: 'support.dolphindev.ir')));
    expect(find.text('Ab3dE6gh'), findsOneWidget);
    expect(find.textContaining('پشت تلفن نخوانید'), findsOneWidget);
    await tester.tap(find.byTooltip('کپی رمز'));
    expect(copied, isTrue);
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '', siteLabel: 'x')));
    expect(find.text('رمز یک‌بارمصرف'), findsNothing);
  });
}
