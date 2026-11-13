import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/permissions.dart';
import 'package:flutter_hbb/dolphin/session_controls.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

DolphinSessionView _session({
  bool paused = false,
  ValueChanged<bool>? onPause,
  String? inputOff,
  VoidCallback? onEnd,
  void Function(String, bool)? onToggle,
}) =>
    DolphinSessionView(
        technician: 'علی رضایی',
        elapsed: const Duration(minutes: 4, seconds: 12),
        keyboard: true,
        clipboard: true,
        file: true,
        paused: paused,
        onPause: onPause,
        inputOff: inputOff,
        onToggle: onToggle ?? (_, __) {},
        onEnd: onEnd ?? () {});

/// Upstream's connection window (kConnectionManagerWindowSizeClosedChat in lib/consts.dart, which these tests do not
/// import: it pulls in the generated bridge).
const _upstream = Size(300, 490);

/// The page area of the small window: the window less upstream's 28 px tab bar (kDesktopRemoteTabBarHeight) and its
/// 1 px border.
final _page = Size(kDolphinSessionWindowSize.width - 2, kDolphinSessionWindowSize.height - 28 - 2);

void main() {
  test('the names match the Rust side (src/dolphin_session_core.rs)', () {
    expect(kDolphinPauseSwitch, 'dolphin_pause');
    expect((kDolphinPauseMsgType, kDolphinPauseMsgPaused, kDolphinPauseMsgResumed),
        ('dolphin-pause', 'dolphin-paused', 'dolphin-resumed'));
  });

  test('DD-36: small window during a live session, full for the prompt and the ended screen', () {
    expect(windowModeFor(authorized: true, disconnected: false), DolphinWindowMode.compact);
    expect(windowModeFor(authorized: false, disconnected: false), DolphinWindowMode.full);
    expect(windowModeFor(authorized: true, disconnected: true), DolphinWindowMode.full);
    // Keeps upstream's width and corner, and is shorter than upstream's window.
    expect(kDolphinSessionWindowSize.width, _upstream.width);
    expect(kDolphinSessionWindowSize.height, lessThan(_upstream.height));
    // Only the tab on screen resizes, and only on a change.
    expect(windowNeedsResize(selected: true, wanted: DolphinWindowMode.compact, current: null), isTrue);
    expect(windowNeedsResize(selected: true, wanted: DolphinWindowMode.compact, current: DolphinWindowMode.compact),
        isFalse);
    expect(windowNeedsResize(selected: false, wanted: DolphinWindowMode.full, current: DolphinWindowMode.compact),
        isFalse);
  });

  test('DD-36: the small window comes back after upstream resets it, but an open chat is left alone', () {
    const seen = Size(450, 570); // what the window reported after the small size was set (150 % scaling)
    expect(windowNeedsRefit(seen: seen, current: seen), isFalse);
    expect(windowNeedsRefit(seen: seen, current: const Size(450, 735)), isTrue); // upstream's 300 × 490 again
    expect(windowNeedsRefit(seen: seen, current: const Size(1050, 735)), isFalse); // the chat is open
    expect(windowNeedsRefit(seen: seen, current: const Size(160, 28)), isFalse); // minimized
    expect(windowNeedsRefit(seen: null, current: const Size(450, 735)), isFalse); // the small size was never set
  });

  testWidgets('DD-36: in the small window «پایان» is on screen, even with both notices shown', (tester) async {
    tester.view.physicalSize = _page;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var ended = false;
    await tester.pumpWidget(_app(_session(
        paused: true, onPause: (_) {}, inputOff: 'علی رضایی خاموش کرد، همین حالا', onEnd: () => ended = true)));
    final end = find.text('پایان');
    expect(end, findsOneWidget);
    final r = tester.getRect(end);
    expect(r.bottom, lessThanOrEqualTo(_page.height));
    expect(r.top, greaterThanOrEqualTo(0));
    await tester.tap(end);
    expect(ended, isTrue);
  });

  testWidgets('DD-46: «مکث» pauses, then the window says so and offers «ادامه»', (tester) async {
    final got = <bool>[];
    await tester.pumpWidget(_app(_session(onPause: got.add)));
    expect(find.text(kDolphinPausedTitle), findsNothing);
    expect(find.text(kDolphinPauseHint), findsOneWidget);
    await tester.tap(find.text(kDolphinPauseLabel));
    expect(got, [true]);
    await tester.pumpWidget(_app(_session(paused: true, onPause: got.add)));
    expect(find.text(kDolphinPausedNote), findsOneWidget);
    expect(find.textContaining(kDolphinPausedTitle), findsWidgets); // the badge and the notice
    expect(find.text(kDolphinPauseLabel), findsNothing);
    await tester.tap(find.text(kDolphinResumeLabel));
    expect(got, [true, false]);
  });

  testWidgets('DD-46: no «مکث» where there is no picture to stop (a file-transfer tab)', (tester) async {
    await tester.pumpWidget(_app(_session()));
    expect(find.text(kDolphinPauseLabel), findsNothing);
    expect(find.text('پایان'), findsOneWidget);
  });

  testWidgets('DD-45: each permission has its own switch, also during a pause', (tester) async {
    final got = <String, bool>{};
    await tester.pumpWidget(_app(_session(paused: true, onPause: (_) {}, onToggle: (n, v) => got[n] = v)));
    expect(find.byType(Switch), findsNWidgets(3));
    for (final (_, label) in kDolphinPermissionLabels) {
      await tester.tap(find.text(label));
    }
    expect(got, {'keyboard': false, 'clipboard': false, 'file': false});
  });

  testWidgets('DD-37: the input-off notice says who and since when, and how to get it back', (tester) async {
    await tester.pumpWidget(_app(_session(inputOff: 'علی رضایی خاموش کرد، ۳ دقیقه پیش')));
    expect(find.text(kDolphinInputOffTitle), findsOneWidget);
    expect(find.text('علی رضایی خاموش کرد، ۳ دقیقه پیش'), findsOneWidget);
    expect(find.text(kDolphinInputOffHint), findsOneWidget);
    await tester.pumpWidget(_app(_session()));
    expect(find.text(kDolphinInputOffTitle), findsNothing);
  });

  test('DD-37: since when, kept from the first sight until the block ends; Persian digits', () {
    final t0 = DateTime(2026, 11, 13, 10, 0);
    expect(inputOffSince(null, true, t0), t0);
    expect(inputOffSince(t0, true, t0.add(const Duration(minutes: 5))), t0);
    expect(inputOffSince(t0, false, t0.add(const Duration(minutes: 5))), isNull);
    expect(agoText(t0, t0.add(const Duration(seconds: 59))), 'همین حالا');
    expect(agoText(t0, t0.add(const Duration(minutes: 3, seconds: 10))), '۳ دقیقه پیش');
    expect(agoText(t0, t0.add(const Duration(hours: 1))), '۱ ساعت پیش');
    expect(agoText(t0, t0.add(const Duration(hours: 1, minutes: 5))), '۱ ساعت و ۵ دقیقه پیش');
    expect(agoText(t0, t0.subtract(const Duration(minutes: 1))), 'همین حالا'); // a clock that went back
    expect(inputOffDetail('علی رضایی', t0, t0.add(const Duration(minutes: 12))), 'علی رضایی خاموش کرد، ۱۲ دقیقه پیش');
  });

  test('DD-46: the technician app reads only its own pause messages', () {
    expect(dolphinPauseFromMsgBox('dolphin-pause', 'dolphin-paused'), isTrue);
    expect(dolphinPauseFromMsgBox('dolphin-pause', 'dolphin-resumed'), isFalse);
    expect(dolphinPauseFromMsgBox('error', 'dolphin-paused'), isNull);
    expect(dolphinPauseFromMsgBox('dolphin-pause', 'Connection Error'), isNull);
    expect(dolphinPauseFromMsgBox(null, null), isNull);
  });

  testWidgets('DD-46: the technician sees «مشتری مکث کرد» over the picture, and the strip still shows', (tester) async {
    await tester.pumpWidget(_app(const DolphinPermissionStrip(
        permissions: {'keyboard': false, 'clipboard': false, 'file': false}, paused: true)));
    expect(find.text(kDolphinCustomerPaused), findsOneWidget);
    expect(find.text(kDolphinCustomerPausedNote), findsOneWidget);
    expect(find.byIcon(Icons.block), findsNWidgets(3));
    await tester.pumpWidget(_app(const DolphinPermissionStrip(permissions: {})));
    expect(find.text(kDolphinCustomerPaused), findsNothing);
    // Never shown before the peer info is set.
    await tester.pumpWidget(_app(const DolphinPermissionStrip(permissions: {}, ready: false, paused: true)));
    expect(find.text(kDolphinCustomerPaused), findsNothing);
  });

  testWidgets('the session window on a dark Windows: notices and switches are readable', (tester) async {
    await tester.pumpWidget(darkApp(_session(paused: true, onPause: (_) {}, inputOff: 'علی خاموش کرد، همین حالا')));
    expectAllTextReadable(tester);
  });

  testWidgets('the technician pause card is readable', (tester) async {
    await tester.pumpWidget(darkApp(const DolphinPermissionStrip(permissions: {}, paused: true)));
    for (final t in [kDolphinCustomerPaused, kDolphinCustomerPausedNote]) {
      expect(textContrast(tester, find.text(t)), greaterThanOrEqualTo(4.5), reason: t);
    }
  });
}
