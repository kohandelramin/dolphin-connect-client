import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/demo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// Plan 19 (D1–D2): «ارائه دمو».
void main() {
  test('the session value and the dashboard intent name the screens and the PC', () {
    expect(demoScreensValue(true), 'all');
    expect(demoScreensValue(false), 'primary');
    expect(demoIntentValue('123 456 789', false), 'primary:123456789');
    expect(demoIntentValue('987', true), 'all:987');
  });

  test('what the customer PC said at login decides before anything is asked', () {
    expect(demoCapability(true), DemoCapability.yes);
    expect(demoCapability(false), DemoCapability.x86, reason: 'the x86 (Sciter) build says false');
    expect(demoCapability(null), DemoCapability.old, reason: 'an older app says nothing');
    expect(demoCapability('true'), DemoCapability.old);
    expect(kDemoUnsupported, 'دمو برای این رایانه (ویندوز ۷/۸) در دسترس نیست');
  });

  test('the PC answers: waiting, accepted, the ones that end the connection, a plain line for anything odd', () {
    final asking = demoAnswerFromMsgBox(kDolphinDemoKey, 'asking', 'از مشتری پرسیده شد؛ منتظر «دیدن» است.')!;
    expect(asking.waiting, isTrue);
    expect(asking.closes, isFalse);
    final accepted = demoAnswerFromMsgBox(kDolphinDemoKey, 'accepted', 'دیدن')!;
    expect(accepted.accepted, isTrue);
    expect(accepted.closes, isTrue);
    for (final code in ['refused', 'no-answer']) {
      final a = demoAnswerFromMsgBox(kDolphinDemoKey, code, 'x')!;
      expect(a.closes, isTrue, reason: code);
      expect(a.accepted || a.waiting, isFalse, reason: code);
    }
    for (final code in ['unsupported', 'paused', 'busy', 'no-window', 'not-started', 'running']) {
      final a = demoAnswerFromMsgBox(kDolphinDemoKey, code, 'x')!;
      expect(a.closes || a.accepted || a.waiting, isFalse, reason: code);
    }
    expect(demoAnswerFromMsgBox(kDolphinDemoKey, 'refused', 'x' * 500)!.text, 'مشتری دمو را نپذیرفت.');
    expect(demoAnswerFromMsgBox(kDolphinDemoKey, 'whatever', '')!.text, 'دمو شروع نشد.');
    expect(demoAnswerFromMsgBox(kDolphinDemoKey, 'refused', 'a\nb')!.text, 'a b');
    expect(demoAnswerFromMsgBox('dolphin-safe-mode', 'refused', 'x'), isNull);
    expect(demoAnswerFromMsgBox('error', 'Connection Error', 'x'), isNull);
    expect(demoAnswerFromMsgBox(kDolphinDemoKey, null, 'x'), isNull);
  });

  test('the bar counts in Persian digits', () {
    expect(demoElapsed(const Duration(minutes: 2, seconds: 14)), '۰۲:۱۴');
    expect(demoElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)), '۱:۰۲:۰۳');
    expect(demoElapsed(const Duration(seconds: -5)), '۰۰:۰۰');
    expect(demoBarText('PC-RECEPTION', const Duration(seconds: 134)),
        'در حال نمایش صفحه‌ی شما به \u2068PC-RECEPTION\u2069 · ۰۲:۱۴');
    expect(demoWindowTitle('علی رضایی'), 'دمو از دلفین — علی رضایی');
  });

  test('the customer has a minute to answer', () {
    final t = DateTime(2026, 11, 14, 10);
    expect(demoSecondsLeft(t, t), 60);
    expect(demoSecondsLeft(t, t.add(const Duration(seconds: 59))), 1);
    expect(demoSecondsLeft(t, t.add(const Duration(seconds: 60))), 0);
    expect(demoSecondsLeft(t, t.subtract(const Duration(seconds: 3))), 60);
  });

  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(460, 600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(lightApp(child));
  }

  testWidgets('D1: the technician sees which PC, that the customer only watches, and chooses his screens', (tester) async {
    final fired = <String>[];
    bool? all;
    await pump(
        tester,
        DolphinDemoConfirmView(
            peerName: 'PC-RECEPTION',
            allScreens: false,
            onAllScreens: (v) => all = v,
            onStart: () => fired.add('start'),
            onCancel: () => fired.add('cancel')));
    expect(find.text('ارائه دمو به PC-RECEPTION'), findsOneWidget);
    expect(find.text(kDemoConfirmLine), findsOneWidget);
    expect(find.text(kDemoAllScreensOff), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dolphin-demo-all-screens')));
    expect(all, isTrue);
    await tester.tap(find.text(kDemoStart));
    await tester.tap(find.text(kDemoCancel));
    expect(fired, ['start', 'cancel']);
  });

  testWidgets('D1: the red bar names the PC, counts, and ends in one click', (tester) async {
    var ended = 0;
    await pump(tester,
        DolphinDemoBar(peerName: 'PC-RECEPTION', elapsed: const Duration(seconds: 134), onEnd: () => ended++),
        size: const Size(560, 44));
    expect(find.text(demoBarText('PC-RECEPTION', const Duration(seconds: 134))), findsOneWidget);
    await tester.tap(find.text(kDemoEnd));
    expect(ended, 1);
    expect(tester.takeException(), isNull);
    expect(contrast(Colors.white, DolphinDemoBar.red), greaterThanOrEqualTo(4.5));
  });

  testWidgets('the wait and the PC\'s last word in the technician\'s session', (tester) async {
    var cancelled = 0, closed = 0;
    await pump(tester, DolphinDemoWaitView(text: kDemoAsking, onCancel: () => cancelled++));
    expect(find.text(kDemoAsking), findsOneWidget);
    await tester.tap(find.text(kDemoWaitCancel));
    expect(cancelled, 1);
    await pump(tester, DolphinDemoAnswerView(text: 'مشتری دمو را نپذیرفت.', onClose: () => closed++));
    expect(find.text('مشتری دمو را نپذیرفت.'), findsOneWidget);
    await tester.tap(find.text(kDemoClose));
    expect(closed, 1);
  });

  testWidgets('D2: the customer is asked first; «دیدن» and «نه»', (tester) async {
    final fired = <String>[];
    await pump(
        tester,
        DolphinDemoAskView(
            technician: 'علی رضایی',
            canSee: true,
            secondsLeft: 42,
            phone: '021-44280505',
            onSee: () => fired.add('see'),
            onNo: () => fired.add('no')),
        size: const Size(300, 380));
    expect(find.text('علی رضایی می‌خواهد صفحه‌ی خودش را به شما نشان دهد'), findsOneWidget);
    expect(find.text(kDemoAskHint), findsOneWidget);
    expect(find.text('۴۲ ثانیه'), findsOneWidget);
    expect(find.text(kDemoNotVerified, findRichText: false), findsNothing);
    await tester.tap(find.text(kDemoSee));
    await tester.tap(find.text(kDemoNo));
    expect(fired, ['see', 'no']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D2: no «دیدن» for a technician the portal did not vouch for; «نه» still works', (tester) async {
    var no = 0;
    await pump(
        tester,
        DolphinDemoAskView(
            technician: '987654321',
            canSee: false,
            secondsLeft: 60,
            phone: '021-44280505',
            onSee: () => fail('must not be offered'),
            onNo: () => no++),
        size: const Size(300, 380));
    expect(find.text(kDemoSee), findsNothing);
    expect(find.textContaining('۰۲۱-۴۴۲۸۰۵۰۵'), findsOneWidget);
    await tester.tap(find.text(kDemoNo));
    expect(no, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('D2: the demo window strip, view only, screens only when allowed, «پایان دمو»', (tester) async {
    var ended = 0;
    final picked = <int>[];
    await pump(tester, DolphinDemoWindowBar(title: demoWindowTitle('علی رضایی'), onEnd: () => ended++),
        size: const Size(640, 60));
    expect(find.text('دمو از دلفین — علی رضایی'), findsOneWidget);
    expect(find.text(kDemoViewOnly), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.text(kDemoEnd));
    expect(ended, 1);

    await pump(tester, DolphinDemoWindowBar(title: 'x', screens: 2, current: 0, onScreen: picked.add, onEnd: () {}),
        size: const Size(640, 60));
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    await tester.tap(find.text('صفحه‌ی ۲'));
    expect(picked, [1]);

    await pump(tester, DolphinDemoWindowBar(title: 'x', screens: 3, onEnd: () {}), size: const Size(640, 60));
    expect(find.byType(ChoiceChip), findsNothing, reason: 'no picker without the technician\'s «همه‌ی صفحه‌های من»');
    expect(tester.takeException(), isNull);
  });

  testWidgets('D2: the end of the demo, or a failure to connect, in Persian', (tester) async {
    var closed = 0;
    await pump(tester, DolphinDemoEndedView(wasConnected: true, onClose: () => closed++));
    expect(find.text(kDemoEnded), findsOneWidget);
    await tester.tap(find.text(kDemoClose));
    expect(closed, 1);
    await pump(tester, DolphinDemoEndedView(wasConnected: false, onClose: () {}));
    expect(find.text(kDemoNotConnected), findsOneWidget);
  });
}
