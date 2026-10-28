import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/permissions.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/verify.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  testWidgets('during the session the customer can switch every permission', (tester) async {
    final got = <String, bool>{};
    await tester.pumpWidget(_app(DolphinSessionView(
        technician: 'علی رضایی',
        elapsed: const Duration(minutes: 4, seconds: 12),
        keyboard: true,
        clipboard: true,
        file: false,
        onToggle: (name, enabled) => got[name] = enabled,
        onEnd: () {})));
    expect(find.text('۰۴:۱۲'), findsOneWidget);
    await tester.tap(find.text('موس و صفحه‌کلید'));
    await tester.tap(find.text('کلیپ‌بورد'));
    await tester.tap(find.text('انتقال فایل'));
    expect(got, {'keyboard': false, 'clipboard': false, 'file': true});
  });

  test('the timer reads the clock from the start, in Persian digits', () {
    final start = DateTime(2026, 10, 27, 10, 0, 0);
    expect(sessionElapsed(start, DateTime(2026, 10, 27, 11, 2, 3)), const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(sessionElapsed(null, DateTime(2026, 10, 27)), Duration.zero);
    expect(sessionClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '۱:۰۲:۰۳');
    expect(sessionClock(const Duration(seconds: 59)), '۰۰:۵۹');
  });

  testWidgets('the elevation button says what it is for', (tester) async {
    var elevated = false;
    await tester.pumpWidget(_app(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.verified, 'علی'),
        peerName: 'x',
        showElevate: true,
        onAccept: (k, c, f) {},
        onAcceptElevate: (k, c, f) => elevated = true,
        onDeny: () {})));
    await tester.tap(find.text('پذیرفتن، با اجازه‌ی نصب برنامه'));
    expect(elevated, isTrue);
  });

  test('the technician sees what the customer allows; unknown counts as allowed', () {
    expect(permissionStates({'keyboard': true, 'clipboard': false}),
        [('موس و صفحه‌کلید', true), ('کلیپ‌بورد', false), ('انتقال فایل', true)]);
  });

  testWidgets('the strip in the technician window marks what is off', (tester) async {
    await tester.pumpWidget(_app(const DolphinPermissionStrip(permissions: {'file': false})));
    expect(find.text('انتقال فایل'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
  });

  test('why the session ended', () {
    expect(endReason(byCustomer: true, verdictNow: TechCheck.verified, sinceEndMs: 0), DolphinEndReason.you);
    // The portal no longer vouches for this peer: it cut the connection.
    expect(endReason(byCustomer: false, verdictNow: TechCheck.rejected, sinceEndMs: 0), DolphinEndReason.portal);
    // Still vouched for: wait for the heartbeat that may bring the portal's word, then it was the technician.
    expect(endReason(byCustomer: false, verdictNow: TechCheck.verified, sinceEndMs: 1000), isNull);
    expect(endReason(byCustomer: false, verdictNow: TechCheck.verified, sinceEndMs: kDolphinEndSettleMs),
        DolphinEndReason.technician);
    expect(endReason(byCustomer: false, verdictNow: TechCheck.unverifiable, sinceEndMs: kDolphinEndSettleMs),
        DolphinEndReason.technician);
  });

  testWidgets('the ended screen names who ended it', (tester) async {
    for (final (reason, text) in [
      (DolphinEndReason.you, 'شما پایان دادید.'),
      (DolphinEndReason.technician, 'اتصال کارشناس بسته شد.'),
      (DolphinEndReason.portal, 'پورتال دلفین این اتصال را قطع کرد.'),
    ]) {
      await tester.pumpWidget(_app(DolphinEndedView(reason: reason, onClose: () {})));
      expect(find.text('جلسه پایان یافت.'), findsOneWidget);
      expect(find.text(text), findsOneWidget);
    }
    var closed = false;
    await tester.pumpWidget(_app(DolphinEndedView(reason: null, onClose: () => closed = true)));
    expect(find.text('جلسه پایان یافت.'), findsOneWidget);
    await tester.tap(find.text('بستن'));
    expect(closed, isTrue);
  });

  testWidgets('the ended screen closes itself after a minute, once', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_app(DolphinEndedView(reason: DolphinEndReason.you, onClose: () => closed++)));
    await tester.pump(const Duration(milliseconds: kDolphinEndedAutoCloseMs - 1000));
    expect(closed, 0);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(closed, 1);
    await tester.pump(const Duration(minutes: 2));
    expect(closed, 1);
  });

  testWidgets('closing by the button first cancels the automatic close', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_app(DolphinEndedView(reason: null, onClose: () => closed++)));
    await tester.tap(find.text('بستن'));
    expect(closed, 1);
    await tester.pumpWidget(_app(const SizedBox()));
    await tester.pump(const Duration(minutes: 2));
    expect(closed, 1);
  });
}
