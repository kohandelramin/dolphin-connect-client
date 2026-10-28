import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/panel_bridge.dart';
import 'package:flutter_hbb/dolphin/technician_id.dart';
import 'package:flutter_hbb/dolphin/verify.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  test('server status maps to the three states', () {
    expect(serverStateFromStatus(1), DolphinServerState.ready);
    expect(serverStateFromStatus(0), DolphinServerState.connecting);
    expect(serverStateFromStatus(-1), DolphinServerState.offline);
  });

  test('IDs are grouped in threes for reading aloud', () {
    expect(groupId('123456789'), '123 456 789');
    expect(groupId('1234567890'), '1 234 567 890');
    expect(groupId('abc-12'), 'abc-12');
  });

  test('support numbers pushed by the portal win over the compiled one', () {
    expect(supportPhone('021-44200250 · 0912-0000000', '021-44200250'), '021-44200250 · 0912-0000000');
    expect(supportPhone('  ', '021-44200250'), '021-44200250');
  });

  test('the theme uses Vazirmatn and azure', () {
    final t = dolphinTheme(ThemeData.light());
    expect(t.textTheme.bodyMedium?.fontFamily, kDolphinFont);
    expect(t.colorScheme.primary, DolphinColors.azure);
  });

  testWidgets('home shows the grouped ID, status and footer; copy works',
      (tester) async {
    var copied = false;
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.ready,
        onCopy: () => copied = true,
        phone: '021-12345678',
        siteLabel: 'support.dolphindev.ir')));
    expect(find.text('123 456 789'), findsOneWidget);
    expect(find.textContaining('آماده'), findsOneWidget);
    expect(find.textContaining('021-12345678'), findsOneWidget);
    await tester.tap(find.text('کپی شناسه'));
    expect(copied, isTrue);
  });

  testWidgets('home opens the request section when asked, and hides the button otherwise', (tester) async {
    var opened = false;
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.ready,
        onCopy: () {},
        onRequests: () => opened = true,
        phone: '',
        siteLabel: 'support.dolphindev.ir')));
    await tester.tap(find.text('درخواست‌ها و پیام‌ها'));
    expect(opened, isTrue);
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '', siteLabel: 'x')));
    expect(find.text('درخواست‌ها و پیام‌ها'), findsNothing);
  });

  test('the customer app only answers hello with its own ID and never connects out', () {
    expect(customerReply(const PanelMessage('dolphin-hello'), '123456789'), '{"type":"dolphin-id","id":"123456789"}');
    expect(customerReply(const PanelMessage('dolphin-connect', '987654321'), '123456789'), isNull);
    expect(customerReply(const PanelMessage('dolphin-hello'), ''), isNull);
  });

  testWidgets('home says when the server is unreachable', (tester) async {
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.offline,
        onCopy: () {},
        phone: '',
        siteLabel: 'support.dolphindev.ir')));
    expect(find.textContaining('وصل نیست'), findsOneWidget);
  });

  testWidgets('verified prompt: portal name, file transfer off by default, accept passes the toggles',
      (tester) async {
    List<bool>? got;
    var denied = false;
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.verified, 'رحمت کهندل'),
        peerName: 'DESKTOP-A1',
        onAccept: (k, c, f) => got = [k, c, f],
        onDeny: () => denied = true)));
    expect(find.textContaining('رحمت کهندل از دلفین'), findsOneWidget);
    expect(find.textContaining('DESKTOP-A1'), findsNothing);
    await tester.tap(find.text('پذیرفتن'));
    expect(got, [true, true, false]);
    await tester.tap(find.text('رد'));
    expect(denied, isTrue);
  });

  testWidgets('a connection the portal did not authorize has no Accept button', (tester) async {
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.rejected),
        peerName: 'Dolphin Support',
        onAccept: (k, c, f) {},
        onDeny: () {})));
    expect(find.textContaining('از کارشناس دلفین نیست'), findsOneWidget);
    expect(find.text('پذیرفتن'), findsNothing);
    expect(find.text('رد'), findsOneWidget);
  });

  testWidgets('while checking, only Deny is offered', (tester) async {
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.checking), peerName: 'x', onAccept: (k, c, f) {}, onDeny: () {})));
    expect(find.textContaining('در حال بررسی'), findsOneWidget);
    expect(find.text('پذیرفتن'), findsNothing);
  });

  test('the panel may only ask to connect to a valid ID or say hello', () {
    expect(parsePanelMessage({'type': 'dolphin-connect', 'id': '123 456 789'})?.id, '123456789');
    expect(parsePanelMessage('{"type":"dolphin-connect","id":"123456789"}')?.type, 'dolphin-connect');
    expect(parsePanelMessage({'type': 'dolphin-hello'})?.type, 'dolphin-hello');
    expect(parsePanelMessage({'type': 'dolphin-connect', 'id': 'x;rm'}), isNull);
    expect(parsePanelMessage({'type': 'other'}), isNull);
    expect(parsePanelMessage('not json'), isNull);
  });

  test('the panel stays on the portal', () {
    const portal = 'https://support.dolphindev.ir';
    expect(isPanelUrl('https://support.dolphindev.ir/staff/computers', portal), isTrue);
    expect(isPanelUrl('https://support.dolphindev.ir', portal), isTrue);
    expect(isPanelUrl('https://support.dolphindev.ir.evil.example/', portal), isFalse);
    expect(isPanelUrl('https://example.com/', portal), isFalse);
  });

  test('the portal decides who may connect', () {
    TechVerdict v(String techId, {String peer = '287654321', int until = 2000, int now = 1000, int waited = 7000}) =>
        verifyTechnician(peerId: peer, techId: techId, techName: 'رحمت', until: until, nowSeconds: now, waitedMs: waited);
    expect(v('287654321').state, TechCheck.verified);
    expect(v('287654321').name, 'رحمت');
    expect(v('').state, TechCheck.unverifiable); // never heard from the portal
    expect(v('-').state, TechCheck.checking); // nobody yet: wait for the next heartbeat
    expect(v('-', waited: 7000).state, TechCheck.rejected);
    expect(v('111111111', waited: 7000).state, TechCheck.rejected); // someone else
    expect(v('287654321', now: 3000, waited: 7000).state, TechCheck.rejected); // authorization expired
  });

  testWidgets('technician build shows its own ID with copy', (tester) async {
    var copied = false;
    await tester.pumpWidget(_app(DolphinTechnicianIdView(id: '287654321', onCopy: () => copied = true)));
    expect(find.text('287 654 321'), findsOneWidget);
    expect(find.textContaining('حساب من'), findsOneWidget);
    await tester.tap(find.text('کپی'));
    expect(copied, isTrue);
  });

  testWidgets('session view shows the technician, time and End', (tester) async {
    var ended = false;
    await tester.pumpWidget(_app(DolphinSessionView(
        technician: 'علی رضایی',
        elapsed: const Duration(minutes: 4, seconds: 12),
        keyboard: true,
        clipboard: true,
        file: false,
        onToggle: (_, __) {},
        onEnd: () => ended = true)));
    expect(find.text('۰۴:۱۲'), findsOneWidget);
    await tester.tap(find.text('پایان'));
    expect(ended, isTrue);
  });

  // D5 (WF-11): Accept needs the portal's word on who the technician is, in every approve mode. Code mode stays
  // usable because a valid code is authorised in Rust before any prompt; this prompt only serves a peer without one.
  test('Accept only for a verified technician', () {
    expect(acceptAllowed(const TechVerdict(TechCheck.verified, 'x')), isTrue);
    expect(acceptAllowed(const TechVerdict(TechCheck.verified)), isTrue);
    expect(acceptAllowed(const TechVerdict(TechCheck.unverifiable)), isFalse);
    expect(acceptAllowed(const TechVerdict(TechCheck.checking)), isFalse);
    expect(acceptAllowed(const TechVerdict(TechCheck.rejected)), isFalse);
  });

  test('portal down: a stale answer is unverifiable, a valid unexpired one still verifies', () {
    TechVerdict v(String techId, {bool down = true, String peer = '287654321', int until = 2000, int now = 1000, int waited = 7000}) =>
        verifyTechnician(
            peerId: peer, techId: techId, techName: 'رحمت', until: until, nowSeconds: now, waitedMs: waited, portalDown: down);
    expect(v('-').state, TechCheck.unverifiable); // stale "nobody" while the portal is unreachable
    expect(v('-', waited: 7000).state, TechCheck.unverifiable); // never «این اتصال از کارشناس دلفین نیست»
    expect(v('111111111', waited: 7000).state, TechCheck.unverifiable);
    expect(v('287654321', now: 3000, waited: 7000).state, TechCheck.unverifiable); // expired
    expect(v('287654321').state, TechCheck.verified); // the portal vouched, not expired
    expect(v('').state, TechCheck.unverifiable);
    // The portal is reachable again (option cleared): the old rules apply.
    expect(v('-', down: false, waited: 0).state, TechCheck.checking);
    expect(v('-', down: false, waited: 7000).state, TechCheck.rejected);
  });

  test('a new prompt shows "checking" first, even with the portal down; neither state accepts', () {
    TechVerdict v(int waited) => verifyTechnician(
        peerId: '287654321', techId: '-', techName: '-', until: 0, nowSeconds: 1000, waitedMs: waited, portalDown: true);
    expect(v(0).state, TechCheck.checking);
    expect(v(5999).state, TechCheck.checking);
    expect(v(6000).state, TechCheck.unverifiable); // after the wait the outage text
    expect(acceptAllowed(v(0)), isFalse);
    expect(acceptAllowed(v(6000)), isFalse);
  });

  testWidgets('unverifiable (the default code mode too): no Accept, the message and the phone, Deny works', (tester) async {
    var denied = false;
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.unverifiable),
        peerName: 'x',
        phone: '021-44200250',
        onAccept: (k, c, f) {},
        onDeny: () => denied = true)));
    expect(find.textContaining('پورتال دلفین در دسترس نیست؛ با دلفین تماس بگیرید.'), findsOneWidget);
    expect(find.textContaining('۰۲۱-۴۴۲۰۰۲۵۰'), findsOneWidget);
    expect(find.text('پذیرفتن'), findsNothing);
    await tester.tap(find.text('رد'));
    expect(denied, isTrue);
  });

  testWidgets('portal down with a stale "-" tech ID shows the D5 message and phone, not the rejection', (tester) async {
    final verdict = verifyTechnician(
        peerId: '287654321', techId: '-', techName: '-', until: 0, nowSeconds: 1000, waitedMs: 9000, portalDown: true);
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: verdict, peerName: 'x', phone: '021-44200250', onAccept: (k, c, f) {}, onDeny: () {})));
    expect(find.textContaining('پورتال دلفین در دسترس نیست'), findsOneWidget);
    expect(find.textContaining('۰۲۱-۴۴۲۰۰۲۵۰'), findsOneWidget);
    expect(find.textContaining('این اتصال از کارشناس دلفین نیست'), findsNothing);
    expect(find.text('پذیرفتن'), findsNothing);
  });

  testWidgets('a verified technician can be accepted, and Deny is there too', (tester) async {
    var accepted = false;
    var denied = false;
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.verified, 'رحمت'),
        peerName: 'x',
        onAccept: (k, c, f) => accepted = true,
        onDeny: () => denied = true)));
    await tester.tap(find.text('پذیرفتن'));
    expect(accepted, isTrue);
    await tester.tap(find.text('رد'));
    expect(denied, isTrue);
  });
}
