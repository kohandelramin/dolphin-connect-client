import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/health.dart';
import 'package:flutter_hbb/dolphin/health_probe.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/support_upload.dart';
import 'package:flutter_hbb/dolphin/support_views.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Plan 18 Phase 4: DD-38 «بررسی سلامت», DD-19 the stopped service, DD-40 no monitor, and the DD-7 / DD-48 dialogs.

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

DolphinHomeView _home(
        {DolphinServerState state = DolphinServerState.ready,
        VoidCallback? onStartService,
        VoidCallback? onHealth,
        VoidCallback? onReport,
        VoidCallback? onScreenshot,
        String headlessFix = ''}) =>
    DolphinHomeView(
        id: '123456789',
        state: state,
        onCopy: () {},
        phone: '021-44280505',
        siteLabel: 'support.dolphindev.ir',
        onStartService: onStartService,
        onHealth: onHealth,
        onReport: onReport,
        onScreenshot: onScreenshot,
        headlessFix: headlessFix);

void main() {
  group('service (DD-19)', () {
    test('Windows states read as ours', () {
      expect(serviceStateFrom(4), ServiceState.running);
      expect(serviceStateFrom(1), ServiceState.stopped);
      expect(serviceStateFrom(7), ServiceState.stopped);
      for (final s in [2, 3, 5, 6]) {
        expect(serviceStateFrom(s), ServiceState.pending);
      }
      expect(serviceStateFromError(1060), ServiceState.missing);
      expect(serviceStateFromError(5), ServiceState.unknown);
    });

    test('down only for an installed app whose service should run', () {
      expect(serviceDown(installed: true, state: ServiceState.stopped, stopOption: false), isTrue);
      expect(serviceDown(installed: true, state: ServiceState.missing, stopOption: false), isTrue);
      expect(serviceDown(installed: false, state: ServiceState.stopped, stopOption: false), isFalse);
      expect(serviceDown(installed: true, state: ServiceState.stopped, stopOption: true), isFalse); // BL-SVC shows it
      expect(serviceDown(installed: true, state: ServiceState.pending, stopOption: false), isFalse);
      expect(serviceDown(installed: true, state: ServiceState.unknown, stopOption: false), isFalse);
    });

    test('the notice waits for two reads in a row', () {
      final w = ServiceWatch();
      expect(w.note(true), isFalse);
      expect(w.down, isFalse);
      expect(w.note(true), isTrue);
      expect(w.down, isTrue);
      expect(w.note(true), isFalse);
      expect(w.note(false), isTrue);
      expect(w.down, isFalse);
      w.note(true);
      w.note(false);
      expect(w.note(true), isFalse);
    });

    testWidgets('a stopped service shows the red notice with «درست کن»', (tester) async {
      var fixed = 0;
      await tester.pumpWidget(_app(_home(state: DolphinServerState.stopped, onStartService: () => fixed++)));
      expect(find.byKey(const ValueKey('dolphin-service-notice')), findsOneWidget);
      expect(find.text(kServiceStoppedHint), findsOneWidget);
      await tester.tap(find.text(kFixLabel));
      expect(fixed, 1);
      await tester.pumpWidget(_app(_home(onStartService: () {})));
      expect(find.byKey(const ValueKey('dolphin-service-notice')), findsNothing);
    });
  });

  group('no monitor (DD-40)', () {
    test('no screen, or one small stand-in, is headless', () {
      expect(looksHeadless([]), isTrue);
      expect(looksHeadless([(1024, 768)]), isTrue);
      expect(looksHeadless([(800, 600)]), isTrue);
      expect(looksHeadless([(1920, 1080)]), isFalse);
      expect(looksHeadless([(1024, 768), (1024, 768)]), isFalse);
    });

    test('the fix depends on Windows and on being installed', () {
      expect(headlessFix(installed: true, windowsBuild: 19045), contains('مجازی می‌سازد'));
      expect(headlessFix(installed: false, windowsBuild: 19045), contains('نصب کنید'));
      expect(headlessFix(installed: true, windowsBuild: 17763), isNot(contains('مجازی')));
      expect(headlessFix(installed: true, windowsBuild: 0), contains('مجازی'));
    });

    testWidgets('the notice shows only with a fix', (tester) async {
      await tester.pumpWidget(_app(_home(headlessFix: headlessFix(installed: true, windowsBuild: 19045))));
      expect(find.text(kHeadlessTitle), findsOneWidget);
      await tester.pumpWidget(_app(_home()));
      expect(find.byKey(const ValueKey('dolphin-headless-notice')), findsNothing);
    });
  });

  group('health (DD-38)', () {
    test('each check has a Persian result; only the service has a fix', () {
      final items = [
        serviceItem(installed: true, state: ServiceState.stopped, stopOption: false),
        serviceItem(installed: false, state: ServiceState.unknown, stopOption: false),
        registeredItem(false),
        dnsItem('remote.dolphindev.ir', isIp: false, addresses: null),
        dnsItem('1.2.3.4', isIp: true),
        portItem('سرور دلفین', 21116, false),
        diskItem([r'C:\x']),
        displayItem(headless: true, installed: true, windowsBuild: 19045),
      ];
      for (final i in items) {
        expect(i.result, isNotEmpty);
        expect(i.result, matches(RegExp('[آ-ی]')));
      }
      expect(items.where((i) => i.fix != HealthFix.none).length, 1);
      expect(items.first.fix, HealthFix.startService);
      expect(items[1].tone, CheckTone.info);
      expect(portItem('x', 21116, true).result, contains('۲۱۱۱۶'));
      expect(healthSummary([registeredItem(true)]), 'همه چیز درست است.');
      expect(healthSummary(items), contains('مشکل'));
      expect(healthReportName(DateTime(2026, 11, 13, 9, 5)), 'dolphin-health-20261113-0905.txt');
    });

    test('server addresses are split into host and port', () {
      expect(hostPort('remote.dolphindev.ir', 21116), ('remote.dolphindev.ir', 21116));
      expect(hostPort('remote.dolphindev.ir:21200', 21116), ('remote.dolphindev.ir', 21200));
      expect(hostPort('[::1]:21117', 21116), ('::1', 21117));
      expect(hostPort('a.ir, b.ir', 21116), ('a.ir', 21116));
    });

    testWidgets('the list: a spinner, then results, «تعمیر سرویس», «ذخیره‌ی گزارش»', (tester) async {
      HealthFix? fixed;
      var saved = 0;
      await tester.pumpWidget(_app(DolphinHealthView(items: null, onClose: () {})));
      expect(find.text(kCheckingLabel), findsOneWidget);
      expect(find.text(kSaveReportLabel), findsNothing);
      await tester.pumpWidget(_app(DolphinHealthView(
          items: [serviceItem(installed: true, state: ServiceState.stopped, stopOption: false), registeredItem(true)],
          onFix: (f) => fixed = f,
          onSave: () => saved++,
          onAgain: () {},
          onClose: () {},
          saved: 'گزارش روی دسکتاپ ذخیره شد')));
      expect(find.text('۱ مورد مشکل دارد.'), findsOneWidget);
      await tester.tap(find.text(kFixServiceLabel));
      expect(fixed, HealthFix.startService);
      await tester.tap(find.text(kSaveReportLabel));
      expect(saved, 1);
      expect(find.text('گزارش روی دسکتاپ ذخیره شد'), findsOneWidget);
    });

    testWidgets('the dialog runs the checks and saves', (tester) async {
      var runs = 0;
      await tester.pumpWidget(_app(DolphinHealthDialog(
          run: () async {
            runs++;
            return [registeredItem(true)];
          },
          onFix: (_) {},
          onSave: (items) async => 'ذخیره شد ${items.length}',
          onClose: () {})));
      await tester.pump();
      expect(runs, 1);
      expect(find.text('همه چیز درست است.'), findsOneWidget);
      await tester.tap(find.text(kSaveReportLabel));
      await tester.pump();
      expect(find.text('ذخیره شد 1'), findsOneWidget);
      await tester.tap(find.text(kCheckAgainLabel));
      await tester.pump();
      expect(runs, 2);
    });
  });

  group('support tools and uploads (DD-7, DD-48)', () {
    testWidgets('the buttons follow their callbacks', (tester) async {
      await tester.pumpWidget(_app(_home(onHealth: () {}, onReport: () {}, onScreenshot: () {})));
      expect(find.text(kHealthLabel), findsOneWidget);
      expect(find.text(kReportLabel), findsOneWidget);
      expect(find.text(kScreenshotLabel), findsOneWidget);
      // diagnostics-upload hidden: only the health check is left.
      await tester.pumpWidget(_app(_home(onHealth: () {})));
      expect(find.text(kReportLabel), findsNothing);
      expect(find.text(kScreenshotLabel), findsNothing);
      await tester.pumpWidget(_app(_home()));
      expect(find.text(kSupportToolsTitle), findsNothing);
    });

    testWidgets('a report: the note goes with it, the answer is shown, then «بستن»', (tester) async {
      String? sent;
      await tester.pumpWidget(_app(DolphinUploadForm(
          kind: UploadKind.diagnostics,
          onSend: (note) async {
            sent = note;
            return const UploadAnswer(true, 'گزارش فرستاده شد');
          },
          onClose: () {})));
      expect(find.text(kReportBody), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'برنامه بسته می‌شود');
      await tester.tap(find.text(kSendLabel));
      await tester.pump();
      expect(sent, 'برنامه بسته می‌شود');
      expect(find.text('گزارش فرستاده شد'), findsOneWidget);
      expect(find.text(kCloseLabel), findsOneWidget);
      expect(find.text(kSendLabel), findsNothing);
    });

    testWidgets('a refused send keeps «فرستادن» for another try', (tester) async {
      await tester.pumpWidget(_app(DolphinUploadForm(
          kind: UploadKind.diagnostics,
          onSend: (_) async => uploadAnswer(200, '{"ok":false,"reason":"not_linked"}'),
          onClose: () {})));
      await tester.tap(find.text(kSendLabel));
      await tester.pump();
      expect(find.textContaining('سازمان'), findsOneWidget);
      expect(find.text(kSendLabel), findsOneWidget);
    });

    testWidgets('the customer sees the screenshot before sending, and can cancel', (tester) async {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 4)));
      var closed = 0, sent = 0;
      await tester.pumpWidget(_app(DolphinUploadForm(
          kind: UploadKind.screenshot,
          png: png,
          onSend: (_) async {
            sent++;
            return const UploadAnswer(true, 'ok');
          },
          onClose: () => closed++)));
      expect(find.byType(Image), findsOneWidget);
      expect(find.text(kScreenshotBody), findsOneWidget);
      await tester.tap(find.text(kCancelLabel));
      expect(closed, 1);
      expect(sent, 0);
    });
  });
}
