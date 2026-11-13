import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/safe_mode.dart';
import 'package:flutter_hbb/dolphin/session_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// Plan 18 Phase 5 (DD-11): Safe Mode restart and return.
void main() {
  test('the request carries the kind; the window record reads it back', () {
    expect(restartCode(DolphinRestartKind.safe), 'safe');
    expect(restartCode(DolphinRestartKind.normal), 'normal');
    expect(restartKindFrom('safe'), DolphinRestartKind.safe);
    expect(restartKindFrom('normal'), DolphinRestartKind.normal);
    expect(restartKindFrom(''), isNull);
    expect(restartKindFrom(null), isNull);
    expect(restartKindFrom('reboot'), isNull);
  });

  test('the toolbar shows what the customer PC offers; the way back always', () {
    expect(safeModeEntry(peerInSafeMode: false, peerOffers: true), DolphinRestartKind.safe);
    expect(safeModeEntry(peerInSafeMode: false, peerOffers: false), isNull);
    expect(safeModeEntry(peerInSafeMode: null, peerOffers: null), isNull, reason: 'an older customer app says nothing');
    expect(safeModeEntry(peerInSafeMode: true, peerOffers: false), DolphinRestartKind.normal);
    expect(safeModeEntry(peerInSafeMode: true, peerOffers: true), DolphinRestartKind.normal);
  });

  test('the PC answers: tone, waiting, and a plain line for anything odd', () {
    final notice = safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'notice-safe', 'مشتری ۲۰ ثانیه فرصت دارد');
    expect(notice!.tone, SafeModeTone.info);
    expect(notice.waiting, isTrue);
    final going = safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'restarting-safe', 'در حالت امن');
    expect(going!.tone, SafeModeTone.ok);
    expect(going.waiting, isFalse);
    expect(safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'refused-switch', 'خاموش است')!.tone, SafeModeTone.warn);
    expect(safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'cancelled', 'لغو کرد')!.tone, SafeModeTone.warn);
    expect(safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'failed', 'x' * 500)!.text, 'ری‌استارت انجام نشد.');
    expect(safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'failed', 'a\nb')!.text, 'a b');
    expect(safeModeAnswerFromMsgBox('dolphin-panel', 'pasted', 'x'), isNull);
    expect(safeModeAnswerFromMsgBox('error', 'Connection Error', 'x'), isNull);
    expect(safeModeAnswerFromMsgBox(kDolphinSafeModeKey, null, 'x'), isNull);
  });

  test('the customer notice counts twenty seconds down', () {
    final t = DateTime(2026, 11, 13, 10);
    expect(restartSecondsLeft(t, t), 20);
    expect(restartSecondsLeft(t, t.add(const Duration(milliseconds: 999))), 20);
    expect(restartSecondsLeft(t, t.add(const Duration(seconds: 1))), 19);
    expect(restartSecondsLeft(t, t.add(const Duration(seconds: 19))), 1);
    expect(restartSecondsLeft(t, t.add(const Duration(seconds: 20))), 0);
    expect(restartSecondsLeft(t, t.add(const Duration(minutes: 5))), 0);
    expect(restartSecondsLeft(t, t.subtract(const Duration(seconds: 3))), 20);
    expect(restartCountdown(12), '۱۲ ثانیه‌ی دیگر');
    expect(restartCountdown(0), kRestartNoticeNow);
  });

  test('the customer reads what the service said, with the support phone when it did not answer', () {
    expect(customerReturnText('restarting', '021-44280505'), contains('دوباره راه‌اندازی'));
    expect(customerReturnText('not-safe', '021-44280505'), contains('در حالت امن نیست'));
    expect(customerReturnText('no-service', '021-44280505'), contains('۰۲۱-۴۴۲۸۰۵۰۵'));
    expect(customerReturnText('stale', '021-44280505'), contains('سرویس دلفین کانکت پاسخ نداد'));
  });

  Future<void> pump(WidgetTester tester, Widget child, {Size size = const Size(420, 600)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(lightApp(child));
  }

  testWidgets('the technician confirms or cancels', (tester) async {
    final fired = <String>[];
    await pump(
        tester,
        DolphinSafeModeAskView(
            kind: DolphinRestartKind.safe, onConfirm: () => fired.add('yes'), onCancel: () => fired.add('no')));
    expect(find.text(kSafeModeAskTitle), findsOneWidget);
    expect(find.textContaining('۲۰ ثانیه'), findsOneWidget);
    await tester.tap(find.text(kSafeModeRestart));
    await tester.tap(find.text(kSafeModeCancel));
    expect(fired, ['yes', 'no']);
    await pump(tester, DolphinSafeModeAskView(kind: DolphinRestartKind.normal, onConfirm: () {}, onCancel: () {}));
    expect(find.text(kSafeModeReturnTitle), findsOneWidget);
  });

  testWidgets('the answer dialog shows the line and closes', (tester) async {
    var closed = false;
    await pump(
        tester,
        DolphinSafeModeAnswerView(
            answer: const SafeModeAnswer(SafeModeTone.warn, 'مشتری ری‌استارت را لغو کرد.'), onClose: () => closed = true));
    expect(find.text('مشتری ری‌استارت را لغو کرد.'), findsOneWidget);
    await tester.tap(find.text(kSafeModeOk));
    expect(closed, isTrue);
  });

  testWidgets('the customer notice: countdown and «لغو», which is gone at zero', (tester) async {
    var cancelled = 0;
    await pump(
        tester,
        DolphinRestartNoticeView(kind: DolphinRestartKind.safe, secondsLeft: 14, onCancel: () => cancelled++),
        size: const Size(300, 380));
    expect(find.text(kRestartNoticeSafeTitle), findsOneWidget);
    expect(find.text('۱۴ ثانیه‌ی دیگر'), findsOneWidget);
    expect(find.text(kRestartNoticeSafeAfter), findsOneWidget);
    await tester.tap(find.text(kRestartCancel));
    expect(cancelled, 1);
    expect(tester.takeException(), isNull);

    await pump(tester, DolphinRestartNoticeView(kind: DolphinRestartKind.normal, secondsLeft: 0, onCancel: () => cancelled++),
        size: const Size(300, 380));
    expect(find.text(kRestartNoticeNow), findsOneWidget);
    expect(find.text(kRestartNoticeSafeAfter), findsNothing);
    await tester.tap(find.text(kRestartCancel));
    expect(cancelled, 1, reason: 'too late to cancel');
  });

  testWidgets('the home banner in Safe Mode offers the way back', (tester) async {
    var asked = 0;
    await pump(tester, DolphinSafeModeBanner(onReturn: () => asked++, note: 'رایانه چند ثانیه‌ی دیگر دوباره راه‌اندازی می‌شود.'),
        size: const Size(340, 300));
    expect(find.text(kSafeModeBannerTitle), findsOneWidget);
    expect(find.textContaining('چند ثانیه'), findsOneWidget);
    await tester.tap(find.text(kSafeModeBannerReturn));
    expect(asked, 1);

    var confirmed = false;
    await pump(tester, DolphinSafeModeReturnConfirm(onConfirm: () => confirmed = true, onCancel: () {}),
        size: const Size(340, 300));
    await tester.tap(find.text(kSafeModeRestart));
    expect(confirmed, isTrue);
  });

  testWidgets('the toolbar button: hidden without an offer, the right entry with one', (tester) async {
    Future<void> bar(DolphinRestartKind? kind, ValueChanged<DolphinRestartKind>? on) async {
      tester.view.physicalSize = const Size(2400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(lightApp(Center(
          child: DolphinSessionBar(state: const DolphinBarState(), safeMode: kind, onSafeMode: on))));
    }

    final asked = <DolphinRestartKind>[];
    await bar(null, asked.add);
    expect(find.byKey(const ValueKey('dolphin-bar-safe-mode')), findsNothing);
    await bar(DolphinRestartKind.safe, null);
    expect(find.byKey(const ValueKey('dolphin-bar-safe-mode')), findsNothing);
    await bar(DolphinRestartKind.safe, asked.add);
    expect(find.byTooltip(DolphinBarText.safeMode), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dolphin-bar-safe-mode')));
    await bar(DolphinRestartKind.normal, asked.add);
    expect(find.byTooltip(DolphinBarText.safeModeReturn), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dolphin-bar-safe-mode')));
    expect(asked, [DolphinRestartKind.safe, DolphinRestartKind.normal]);
  });
}
