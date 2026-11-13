// Screen previews of the Dolphin customer screens, as PNG files, for a look before any exe is built.
// Off by default (CI and `flutter test` skip it). To write the images:
//   set DOLPHIN_PREVIEW_DIR=E:\dev\previews
//   flutter test test/dolphin/preview_test.dart
// Sample data only; the real Vazirmatn font is loaded from assets/fonts.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/first_run_view.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/network_status.dart';
import 'package:flutter_hbb/dolphin/presence.dart';
import 'package:flutter_hbb/dolphin/recent_sessions.dart';
import 'package:flutter_hbb/dolphin/share.dart';
import 'package:flutter_hbb/dolphin/tech_card.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/verify.dart';
import 'package:flutter_test/flutter_test.dart';

final String? _dir = Platform.environment['DOLPHIN_PREVIEW_DIR'];

Future<void> _loadFonts() async {
  final loader = FontLoader(kDolphinFont);
  for (final f in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Vazirmatn-$f.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
  // Flutter's icon font, so icons show as icons (the real app bundles it).
  final icons = FontLoader('MaterialIcons');
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? r'E:\devlutter';
  icons.addFont(Future.value(ByteData.view(Uint8List.fromList(File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf').readAsBytesSync()).buffer)));
  await icons.load();
}

Future<void> _shot(WidgetTester tester, String name, Size size, Widget child) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dolphinTheme(ThemeData.light()),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(key: key, child: Scaffold(body: child)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  const home = Size(340, 520);
  const homeTall = Size(340, 900);
  const session = Size(300, 380);
  final now = DateTime.now();
  final net = [
    const NetRow('سرور دلفین', 'وصل', tone: NetTone.good),
    const NetRow('نشانی سرور', 'remote.dolphindev.ir', ltr: true),
    const NetRow('IP این رایانه', '192.168.1.24', ltr: true),
  ];
  final recent = [RecentSession(now.subtract(const Duration(hours: 3)), 12, 'علی رضایی')];

  testWidgets('write previews', (tester) async {
    await _loadFonts();
    Directory(_dir!).createSync(recursive: true);

    await _shot(tester, '01-home-ready', homeTall, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '021-44200250', siteLabel: 'support.dolphindev.ir',
        network: net, recent: recent, version: '2.1.0', onStartHere: () {}, onCopyIp: () {}, onCopyDownload: () {}, onCopyGuide: () {},
        onRequests: () {}, onCallback: () {}));
    await _shot(tester, '02-home-tech-coming', home, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '021-44200250', siteLabel: 'support.dolphindev.ir',
        coming: const TechComing('علی رضایی', null), network: net, version: '2.1.0'));
    await _shot(tester, '03-home-connected', home, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '021-44200250', siteLabel: 'support.dolphindev.ir',
        connected: 1, network: net, version: '2.1.0'));
    await _shot(tester, '04-home-offline-id-changed', home, DolphinHomeView(
        id: '987654321', state: DolphinServerState.offline, onCopy: () {}, phone: '021-44200250', siteLabel: 'support.dolphindev.ir',
        idChanged: true, onDismissIdNotice: () {}, network: [const NetRow('سرور دلفین', 'وصل نیست', tone: NetTone.bad)], version: '2.1.0'));
    await _shot(tester, '05-first-run', home, DolphinFirstRunView(id: '123456789', onCopy: () {}, onNext: () {}));
    await _shot(tester, '06-share-stopped', const Size(340, 140), DolphinShareView(stopped: true, onToggle: () {}));
    await _shot(tester, '07-close-question', const Size(360, 300), DolphinCloseDialogView(onChoose: (_, __) {}, onCancel: () {}));
    await _shot(tester, '08-accept-verified', const Size(300, 490), DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.verified, 'علی رضایی'), peerName: 'علی رضایی', onAccept: (_, __, ___) {}, onDeny: () {},
        phone: '021-44200250'));
    await _shot(tester, '09-session', session, DolphinSessionView(
        technician: 'علی رضایی', elapsed: const Duration(minutes: 7, seconds: 12), keyboard: true, clipboard: true, file: true,
        onPause: (_) {}, onToggle: (_, __) {}, onEnd: () {}));
    await _shot(tester, '10-session-paused-input-off', session, DolphinSessionView(
        technician: 'علی رضایی', elapsed: const Duration(minutes: 9), keyboard: false, clipboard: true, file: false, paused: true,
        inputOff: 'علی رضایی خاموش کرد، ۳ دقیقه پیش', onPause: (_) {}, onToggle: (_, __) {}, onEnd: () {}));
    await _shot(tester, '11-ended', session, DolphinEndedView(reason: DolphinEndReason.values.first, onClose: () {}));
  }, skip: _dir == null);
}
