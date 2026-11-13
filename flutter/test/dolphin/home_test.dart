import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/digits.dart';
import 'package:flutter_hbb/dolphin/first_run_view.dart';
import 'package:flutter_hbb/dolphin/home_helpers.dart';
import 'package:flutter_hbb/dolphin/home_status.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/home_widgets.dart';
import 'package:flutter_hbb/dolphin/network_status.dart';
import 'package:flutter_hbb/dolphin/tech_card.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// Plan 18 Phase 2, the customer home: DD-43 status bar, DD-44 readable ID, DD-33 dot and offline bar, DD-8 network
// panel, DD-32 helpers, DD-17 first-run screen.

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

final _jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xD9]);
const _rahmat = TechComing('رحمت کهندل', null);

DolphinHomeView _home({
  DolphinServerState state = DolphinServerState.ready,
  int? connected = 0,
  TechComing? coming,
  List<NetRow> network = const [],
  bool idChanged = false,
  VoidCallback? onDismissIdNotice,
  VoidCallback? onStartHere,
  VoidCallback? onCopyIp,
  VoidCallback? onCopyDownload,
  VoidCallback? onCopyGuide,
  VoidCallback? onCopy,
  String version = '',
}) =>
    DolphinHomeView(
      id: '123456789',
      state: state,
      connected: connected,
      coming: coming,
      onCopy: onCopy ?? () {},
      phone: '021-44200250',
      siteLabel: 'support.dolphindev.ir',
      network: network,
      idChanged: idChanged,
      onDismissIdNotice: onDismissIdNotice,
      onStartHere: onStartHere,
      onCopyIp: onCopyIp,
      onCopyDownload: onCopyDownload,
      onCopyGuide: onCopyGuide,
      version: version,
    );

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

void main() {
  group('DD-44 readable ID', () {
    test('Persian digits in threes on screen, Latin digits on the clipboard', () {
      expect(readableId('123456789'), '۱۲۳ ۴۵۶ ۷۸۹');
      expect(readableId('1234567890'), '۱ ۲۳۴ ۵۶۷ ۸۹۰');
      expect(idForClipboard(readableId('123456789')), '123456789');
      expect(idForClipboard('۱۲۳ ۴۵۶ ۷۸۹'), '123456789');
      expect(idForClipboard('١٢٣ ٤٥٦'), '123456'); // Arabic-Indic too
      expect(idForClipboard('123456789'), '123456789');
      expect(latinDigits('نسخه‌ی ۲.۰.۰'), 'نسخه‌ی 2.0.0');
    });

    testWidgets('home shows the readable ID and a big copy button', (tester) async {
      var copied = false;
      await tester.pumpWidget(_app(_home(onCopy: () => copied = true)));
      expect(find.text('۱۲۳ ۴۵۶ ۷۸۹'), findsOneWidget);
      expect(find.text('123 456 789'), findsNothing);
      expect(find.byType(SelectableText), findsNothing); // the button is the one way to copy the ID
      // FilledButton.icon may build a private subclass, so match by `is`, not by exact type.
      final button = find.ancestor(of: find.text('کپی شناسه'), matching: find.byWidgetPredicate((w) => w is FilledButton));
      expect(button, findsOneWidget);
      expect(tester.getSize(button).width, greaterThan(250));
      await tester.tap(button);
      expect(copied, isTrue);
    });
  });

  group('DD-43 / DD-33 status bar', () {
    final tech = TechComing('رحمت', techPhoto(_jpeg));
    test('the bar follows the server, the session and the technician', () {
      HomeBar bar(DolphinServerState s, int? n, [TechComing? t]) => homeStatus(server: s, connected: n, tech: t).bar;
      expect(bar(DolphinServerState.ready, 0), HomeBar.ready);
      expect(bar(DolphinServerState.ready, 0, tech), HomeBar.coming);
      expect(bar(DolphinServerState.ready, null, tech), HomeBar.ready); // count unknown: no technician card yet
      expect(bar(DolphinServerState.ready, 1, tech), HomeBar.connected);
      expect(bar(DolphinServerState.ready, 2), HomeBar.connected);
      expect(bar(DolphinServerState.connecting, 0, tech), HomeBar.connecting);
      expect(bar(DolphinServerState.offline, 0, tech), HomeBar.offline);
      expect(bar(DolphinServerState.offline, 1, tech), HomeBar.connected); // quieter during a session
      expect(bar(DolphinServerState.stopped, 1, tech), HomeBar.stopped);
    });

    test('the dot is aqua only while the server knows the PC; the quiet line only during a session', () {
      expect(homeStatus(server: DolphinServerState.ready, connected: 0).online, isTrue);
      expect(homeStatus(server: DolphinServerState.connecting, connected: 0).online, isFalse);
      expect(homeStatus(server: DolphinServerState.offline, connected: 0).online, isFalse);
      expect(homeStatus(server: DolphinServerState.offline, connected: 1).quietOffline, isTrue);
      expect(homeStatus(server: DolphinServerState.ready, connected: 1).quietOffline, isFalse);
      expect(homeStatus(server: DolphinServerState.offline, connected: 0).quietOffline, isFalse);
    });

    test('the technician the portal authorized, while the authorization lasts', () {
      const now = 1000000;
      TechComing? at({String id = '123456789', String name = 'رحمت', int until = now + 600}) =>
          authorizedTech(techId: id, techName: name, until: until, nowSeconds: now, photo: _jpeg);
      expect(at()?.name, 'رحمت');
      expect(at()?.photo, isNotNull);
      expect(at(name: '-')?.name, '');
      expect(at(id: '-'), isNull);
      expect(at(id: ''), isNull);
      expect(at(until: now - 3600), isNull);
    });

    test('the second line names the technician', () {
      expect(homeBarDetail(HomeStatus(HomeBar.coming, tech: tech)), startsWith('رحمت اجازه‌ی اتصال دارد'));
      expect(homeBarDetail(const HomeStatus(HomeBar.coming)), startsWith('کارشناس دلفین'));
      expect(homeBarDetail(HomeStatus(HomeBar.connected, tech: tech)), 'رحمت به این رایانه وصل است.');
      expect(homeBarDetail(const HomeStatus(HomeBar.connected)), '');
      expect(homeBarDetail(const HomeStatus(HomeBar.offline)), kBarOfflineHint);
      expect(homeBarDetail(const HomeStatus(HomeBar.ready)), '');
    });

    testWidgets('ready, on the way and connected, with the technician\'s name and photo', (tester) async {
      await tester.pumpWidget(_app(_home()));
      expect(find.text(kBarReady), findsOneWidget);
      expect(find.byType(DolphinTechAvatar), findsNothing);

      await tester.pumpWidget(_app(_home(coming: _rahmat)));
      expect(find.text(kBarComing), findsOneWidget);
      expect(find.textContaining('رحمت کهندل'), findsOneWidget);
      expect(find.byType(DolphinTechAvatar), findsOneWidget);

      await tester.pumpWidget(_app(_home(coming: _rahmat, connected: 1)));
      expect(find.text(kBarConnected), findsOneWidget);
      expect(find.text('رحمت کهندل به این رایانه وصل است.'), findsOneWidget);
      expect(find.text(kBarComing), findsNothing);
      expect(find.byType(DolphinTechAvatar), findsOneWidget);
    });

    testWidgets('no internet: the red bar says what to do; during a session only a quiet line', (tester) async {
      await tester.pumpWidget(_app(_home(state: DolphinServerState.offline)));
      expect(find.text(kBarOffline), findsOneWidget);
      expect(find.text(kBarOfflineHint), findsOneWidget);
      expect(find.text(kWindowOpenLine), findsNothing);
      final bar = tester.widget<Container>(
          find.descendant(of: find.byType(DolphinStatusBar), matching: find.byType(Container)).first);
      expect((bar.decoration as BoxDecoration).color, DolphinColors.dangerSoft);

      await tester.pumpWidget(_app(_home(state: DolphinServerState.offline, connected: 1, coming: _rahmat)));
      expect(find.text(kBarOffline), findsNothing);
      expect(find.text(kBarConnected), findsOneWidget);
      expect(find.text(kBarOfflineQuiet), findsOneWidget);
    });

    testWidgets('the dot uses the portal\'s colours', (tester) async {
      Color dotOf() {
        final dot = tester
            .widgetList<Container>(find.descendant(of: find.byType(DolphinStatusBar), matching: find.byType(Container)))
            .firstWhere((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).shape == BoxShape.circle);
        return (dot.decoration as BoxDecoration).color!;
      }

      await tester.pumpWidget(_app(_home()));
      expect(dotOf(), DolphinColors.aqua);
      await tester.pumpWidget(_app(_home(state: DolphinServerState.offline)));
      expect(dotOf(), DolphinColors.fieldEdge);
      await tester.pumpWidget(_app(_home(state: DolphinServerState.connecting)));
      expect(dotOf(), DolphinColors.fieldEdge);
    });
  });

  group('DD-8 network panel', () {
    test('lines for the server, its address, this PC\'s IP and a changed ID', () {
      final rows = networkRows(
          server: DolphinServerState.ready, serverAddress: 'remote.dolphindev.ir', localIp: '192.168.1.20');
      expect(rows.map((r) => '$r'), [
        'سرور دلفین: وصل و ثبت‌شده',
        'نشانی سرور: remote.dolphindev.ir',
        'IP این رایانه: ۱۹۲.۱۶۸.۱.۲۰',
      ]);
      expect(rows.first.tone, NetTone.good);
      expect(networkRows(server: DolphinServerState.offline, serverAddress: '', localIp: '').map((r) => '$r'),
          ['سرور دلفین: وصل نیست']);
      expect(networkRows(server: DolphinServerState.offline, serverAddress: '', localIp: '').first.tone, NetTone.bad);
      expect(
          networkRows(server: DolphinServerState.ready, serverAddress: '', localIp: '', idChanged: true).last.value,
          'تازه عوض شد');
    });

    test('later phases add their lines; nothing about VPN today', () {
      final rows = networkRows(server: DolphinServerState.ready, serverAddress: 'remote.dolphindev.ir', localIp: '');
      expect(rows.any((r) => r.label.contains('VPN') || r.value.contains('VPN')), isFalse);
      final more = networkRows(
          server: DolphinServerState.ready,
          serverAddress: '',
          localIp: '',
          extra: const [NetRow('آزمایش', 'بله')]);
      expect(more.last.label, 'آزمایش');
    });

    test('only a real local IP is shown', () {
      expect(localIpFrom('192.168.1.20'), '192.168.1.20');
      expect(localIpFrom(' 10.0.0.5 '), '10.0.0.5');
      expect(localIpFrom('fe80::1'), 'fe80::1');
      for (final bad in ['', '-', '127.0.0.1', '0.0.0.0', '::1', '::', 'not an ip', '300.1.1.1']) {
        expect(localIpFrom(bad), '', reason: bad);
      }
    });

    test('the server address without its port; an IP in Persian digits', () {
      expect(serverLabel('remote.dolphindev.ir'), 'remote.dolphindev.ir');
      expect(serverLabel('remote.dolphindev.ir:21116'), 'remote.dolphindev.ir');
      expect(serverLabel('127.0.0.1'), '۱۲۷.۰.۰.۱');
      expect(serverLabel('127.0.0.1:21116'), '۱۲۷.۰.۰.۱');
      expect(serverLabel('[::1]:21116'), '::۱');
      expect(serverLabel('a.example,b.example'), 'a.example');
      expect(serverLabel(''), '');
    });

    testWidgets('the panel shows under the ID with its lines', (tester) async {
      await tester.pumpWidget(_app(_home(
          network: networkRows(
              server: DolphinServerState.ready, serverAddress: 'remote.dolphindev.ir', localIp: '192.168.1.20'))));
      expect(find.text('وضعیت شبکه'), findsOneWidget);
      expect(find.text('وصل و ثبت‌شده'), findsOneWidget);
      expect(find.text('remote.dolphindev.ir'), findsOneWidget);
      expect(find.text('۱۹۲.۱۶۸.۱.۲۰'), findsOneWidget);
      expect(find.textContaining('VPN'), findsNothing);
      expect(tester.getTopLeft(find.text('وضعیت شبکه')).dy, greaterThan(tester.getTopLeft(find.text('کپی شناسه')).dy));
      await tester.pumpWidget(_app(_home()));
      expect(find.text('وضعیت شبکه'), findsNothing);
    });
  });

  group('DD-32 helpers', () {
    test('links to the support site', () {
      final l = DolphinLinks('https://support.dolphindev.ir');
      expect(l.download, 'https://support.dolphindev.ir/download');
      expect(l.guide, 'https://support.dolphindev.ir/help#connect');
      expect(l.help, 'https://support.dolphindev.ir/help');
      expect(DolphinLinks('https://support.dolphindev.ir/').download, 'https://support.dolphindev.ir/download');
    });

    test('the ID notice: nothing on the first run, then only when the ID differs', () {
      IdSeen s(String stored, String current) => idSeen(stored: stored, current: current);
      expect(s('', '123456789').changed, isFalse);
      expect(s('', '123456789').store, '123456789');
      expect(s('123456789', '123456789').changed, isFalse);
      expect(s('123456789', '123456789').store, isNull);
      expect(s('123456789', '987654321').changed, isTrue);
      expect(s('123456789', '987654321').store, '987654321');
      // Not an ID yet (upstream's «Generating ...», or empty): never compared, never stored.
      for (final notYet in ['', 'Generating...', 'در حال ساخت...']) {
        expect(s('123456789', notYet).changed, isFalse, reason: notYet);
        expect(s('123456789', notYet).store, isNull, reason: notYet);
      }
    });

    testWidgets('version, «از اینجا شروع کنید» and the copy buttons', (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(_app(_home(
        version: '2.1.0',
        onStartHere: () => pressed.add('start'),
        onCopyIp: () => pressed.add('ip'),
        onCopyDownload: () => pressed.add('download'),
        onCopyGuide: () => pressed.add('guide'),
      )));
      expect(find.text('نسخه‌ی ۲.۱.۰'), findsOneWidget);
      await _tap(tester, find.text(kStartHereLabel));
      await _tap(tester, find.text(kCopyMyIpLabel));
      await _tap(tester, find.text(kCopyDownloadLabel));
      await _tap(tester, find.text(kCopyGuideLabel));
      expect(pressed, ['start', 'ip', 'download', 'guide']);
    });

    testWidgets('no IP, no «کپی IP من»; no callbacks, no helpers', (tester) async {
      await tester.pumpWidget(_app(_home(onCopyDownload: () {}, onCopyGuide: () {})));
      expect(find.text(kCopyMyIpLabel), findsNothing);
      expect(find.text(kCopyDownloadLabel), findsOneWidget);
      await tester.pumpWidget(_app(_home()));
      expect(find.byType(DolphinHomeHelpers), findsNothing);
      expect(find.textContaining('نسخه‌ی'), findsNothing);
    });

    testWidgets('«شناسه‌ی شما عوض شد» shows and closes', (tester) async {
      var closed = false;
      await tester.pumpWidget(_app(_home(idChanged: true, onDismissIdNotice: () => closed = true)));
      expect(find.text(kIdChangedNotice), findsOneWidget);
      await tester.tap(find.byTooltip('بستن'));
      expect(closed, isTrue);
      await tester.pumpWidget(_app(_home()));
      expect(find.text(kIdChangedNotice), findsNothing);
    });
  });

  group('DD-17 first run', () {
    test('shown until «بعدی» was pressed once', () {
      expect(firstRunShown(''), isTrue);
      expect(firstRunShown('N'), isTrue);
      expect(firstRunShown('Y'), isFalse);
    });

    testWidgets('the ID to copy, two lines of what happens next, «بعدی»', (tester) async {
      var copied = false, next = false;
      await tester.pumpWidget(_app(DolphinFirstRunView(
          id: '123456789', onCopy: () => copied = true, onNext: () => next = true)));
      expect(find.text(kFirstRunTitle), findsOneWidget);
      expect(find.text('۱۲۳ ۴۵۶ ۷۸۹'), findsOneWidget);
      expect(find.text(kFirstRunNext1), findsOneWidget);
      expect(find.text(kFirstRunNext2), findsOneWidget);
      await tester.tap(find.text('کپی شناسه'));
      expect(copied, isTrue);
      await tester.tap(find.text(kFirstRunNextLabel));
      expect(next, isTrue);
    });
  });

  group('DR-1 on a dark Windows', () {
    testWidgets('every new part of the home is readable', (tester) async {
      final rows = networkRows(
          server: DolphinServerState.ready,
          serverAddress: 'remote.dolphindev.ir',
          localIp: '192.168.1.20',
          idChanged: true);
      for (final view in [
        _home(network: rows, idChanged: true, onDismissIdNotice: () {}, version: '2.1.0', onStartHere: () {},
            onCopyIp: () {}, onCopyDownload: () {}, onCopyGuide: () {}),
        _home(coming: _rahmat),
        _home(coming: _rahmat, connected: 1, state: DolphinServerState.offline),
        _home(state: DolphinServerState.offline, network: networkRows(
            server: DolphinServerState.offline, serverAddress: '', localIp: '')),
        _home(state: DolphinServerState.connecting),
      ]) {
        await tester.pumpWidget(darkApp(view));
        expectAllTextReadable(tester);
      }
      await tester.pumpWidget(darkApp(DolphinFirstRunView(id: '123456789', onCopy: () {}, onNext: () {})));
      expectAllTextReadable(tester);
    });

    test('the new colour pairs reach AA', () {
      for (final (fg, bg) in [
        (DolphinColors.amberText, DolphinColors.amberSoft),
        (Colors.white, DolphinColors.azure),
        (DolphinColors.dangerText, Colors.white),
        (DolphinColors.aquaText, Colors.white),
      ]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
      }
    });
  });
}
