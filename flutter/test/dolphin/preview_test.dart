// Screen previews of the Dolphin customer screens, as PNG files, for a look before any exe is built.
// Off by default (CI and `flutter test` skip it). To write the images:
//   set DOLPHIN_PREVIEW_DIR=E:\dev\previews
//   flutter test test/dolphin/preview_test.dart
// Sample data only; the real Vazirmatn font is loaded from assets/fonts.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/dolphin/about.dart';
import 'package:flutter_hbb/dolphin/chat.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/demo.dart';
import 'package:flutter_hbb/dolphin/monitor_picker.dart';
import 'package:flutter_hbb/dolphin/no_picture.dart';
import 'package:flutter_hbb/dolphin/request_outcome.dart';
import 'package:flutter_hbb/dolphin/safe_mode.dart';
import 'package:flutter_hbb/dolphin/session_toolbar.dart';
import 'package:flutter_hbb/dolphin/side_pane.dart';
import 'package:flutter_hbb/dolphin/signin_expired.dart';
import 'package:flutter_hbb/dolphin/tech_theme.dart';
import 'package:flutter_hbb/dolphin/tech_ui/header.dart';
import 'package:flutter_hbb/dolphin/first_run_view.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/network_status.dart';
import 'package:flutter_hbb/dolphin/presence.dart';
import 'package:flutter_hbb/dolphin/printer.dart';
import 'package:flutter_hbb/dolphin/recent_sessions.dart';
import 'package:flutter_hbb/dolphin/share.dart';
import 'package:flutter_hbb/dolphin/sound.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/tech_card.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/theme_tokens.dart';
import 'package:flutter_hbb/dolphin/update_check.dart';
import 'package:flutter_hbb/dolphin/update_view.dart';
import 'package:flutter_hbb/dolphin/verify.dart';
import 'package:flutter_hbb/dolphin/health.dart';
import 'package:flutter_hbb/dolphin/support_upload.dart';
import 'package:flutter_hbb/dolphin/support_views.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

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

Future<void> _shot(WidgetTester tester, String name, Size size, Widget child, {ThemeData? theme, Duration wait = const Duration(milliseconds: 300)}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  final key = GlobalKey();
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? dolphinTheme(ThemeData.light()),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(key: key, child: Scaffold(body: child)),
    ),
  ));
  await tester.pump(wait);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Upstream's chat page draws this bubble around each message (the preview has no chat page).
Widget _bubble(Widget child) => Align(
    alignment: Alignment.centerRight,
    child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: DolphinColors.azure, borderRadius: BorderRadius.circular(12)),
        child: child));

void main() {
  const home = Size(340, 520);
  const homeTall = Size(340, 900);
  const session = Size(300, 380);
  final now = DateTime.now();
  // The customer's network box: the state and this PC's IP only (owner 2026-11-13).
  final net = networkRows(server: DolphinServerState.ready, localIp: '192.168.1.24');
  final recent = [RecentSession(now.subtract(const Duration(hours: 3)), 12, 'علی رضایی')];

  testWidgets('write previews', (tester) async {
    await _loadFonts();
    // The network box's soft glow is a real blurred shadow (tests draw shadows solid by default).
    debugDisableShadows = false;
    Directory(_dir!).createSync(recursive: true);

    await _shot(tester, '01-home-ready', homeTall, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        network: net, recent: recent, version: '2.1.0', onStartHere: () {}, onCopyIp: () {}, onCopyDownload: () {}, onCopyGuide: () {},
        onRequests: () {}, onCallback: () {}));
    await _shot(tester, '02-home-tech-coming', home, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        coming: const TechComing('علی رضایی', null), network: net, version: '2.1.0'));
    await _shot(tester, '03-home-connected', home, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: () {}, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        connected: 1, network: net, version: '2.1.0'));
    await _shot(tester, '04-home-offline-id-changed', home, DolphinHomeView(
        id: '987654321', state: DolphinServerState.offline, onCopy: () {}, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        idChanged: true, onDismissIdNotice: () {}, network: networkRows(server: DolphinServerState.offline, localIp: ''), version: '2.1.0'));
    await _shot(tester, '05-first-run', home, DolphinFirstRunView(id: '123456789', onCopy: () {}, onNext: () {}));
    await _shot(tester, '06-share-stopped', const Size(340, 140), DolphinShareView(stopped: true, onToggle: () {}));
    await _shot(tester, '07-close-question', const Size(360, 300), DolphinCloseDialogView(onChoose: (_, __) {}, onCancel: () {}));
    await _shot(tester, '08-accept-verified', const Size(300, 490), DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.verified, 'علی رضایی'), peerName: 'علی رضایی', onAccept: (_, __, ___) {}, onDeny: () {},
        phone: '021-44280505'));
    await _shot(tester, '09-session', session, DolphinSessionView(
        technician: 'علی رضایی', elapsed: const Duration(minutes: 7, seconds: 12), keyboard: true, clipboard: true, file: true,
        onPause: (_) {}, onToggle: (_, __) {}, onEnd: () {}));
    await _shot(tester, '10-session-paused-input-off', session, DolphinSessionView(
        technician: 'علی رضایی', elapsed: const Duration(minutes: 9), keyboard: false, clipboard: true, file: false, paused: true,
        inputOff: 'علی رضایی خاموش کرد، ۳ دقیقه پیش', onPause: (_) {}, onToggle: (_, __) {}, onEnd: () {}));
    await _shot(tester, '11-ended', session, DolphinEndedView(reason: DolphinEndReason.values.first, onClose: () {}));
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }, skip: _dir == null);

  // Plan 18 Phase 3: the technician's pieces, light and dark (DD-53).
  testWidgets('write technician previews', (tester) async {
    await _loadFonts();
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    const screens = [
      DolphinScreen(x: 0, y: 0, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080),
      DolphinScreen(x: 1920, y: 120, width: 1366, height: 768, pixelWidth: 1366, pixelHeight: 768),
    ];
    for (final dark in [false, true]) {
      final theme = DolphinTechTheme.dataFor(dark ? Brightness.dark : Brightness.light);
      final tag = dark ? 'dark' : 'light';
      await _shot(tester, '20-toolbar-$tag', const Size(1000, 64), DolphinSessionBar(
          state: const DolphinBarState(latencyMs: 45, direct: false, screens: 2, canFollow: true),
          axis: Axis.horizontal, onCtrlAltDel: noop, onLock: noop, onFiles: noop, onViewOnly: noop, onMyCursor: noop,
          onFollow: noop, onNoPicture: noop, onCollapse: noop, onScreenshot: noop, onKeyboardLayout: noop), theme: theme);
      await _shot(tester, '21-monitors-$tag', const Size(360, 240),
          Center(child: DolphinMonitorPicker(screens: screens, current: 0, primary: 0, onPick: (_) {})), theme: theme);
      await _shot(tester, '22-no-picture-$tag', const Size(440, 300),
          Center(child: DolphinNoPictureHelp(canCtrlAltDel: true, installed: true, onCtrlAltDel: noop, onWait: noop, onDisconnect: noop)),
          theme: theme);
      // The technician window's top row with the app's own name (owner 2026-11-13); Plan 19's native header.
      final search = TextEditingController();
      final idField = TextEditingController();
      final focus = FocusNode();
      await _shot(tester, '28-tech-header-$tag', const Size(1120, 56), TechHeader(
          myId: '287654321', staffName: 'علی رضایی', search: search, searchFocus: focus, onSearch: (_) {}, idField: idField,
          onConnect: noop, onDemo: noop, unread: 2, onBell: noop, themeMode: ThemeMode.system, onThemeMode: (_) {},
          onSettings: noop, onCopyId: noop, onSignOut: noop),
          theme: theme);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
      idField.dispose();
      focus.dispose();
    }
    final t = DateTime(2026, 11, 13, 10, 30);
    await _shot(tester, '23-chat', const Size(360, 320), DolphinChatFrame(empty: false, child: ListView(padding: const EdgeInsets.all(8), children: [
      _bubble(DolphinChatText(text: 'سلام، برنامه‌ی حسابداری باز نمی‌شود', at: t)),
      _bubble(DolphinChatText(text: r'C:\Program Files\Dolphin\MS.exe', at: t.add(const Duration(minutes: 1)))),
      _bubble(DolphinChatText(text: 'الان بررسی می‌کنم', at: t.add(const Duration(minutes: 2)))),
    ])));
    await _shot(tester, '24-chat-empty', const Size(360, 200), DolphinChatFrame(empty: true, child: const SizedBox.expand()));
    var calls = 0;
    final start = DateTime(2026, 11, 13, 10, 0);
    await _shot(tester, '25-no-answer', const Size(380, 220),
        Center(child: DolphinWaitAccept(now: () => calls++ < 2 ? start : start.add(const Duration(seconds: 75)))),
        wait: const Duration(milliseconds: 1500));
    await _shot(tester, '26-signin-expired', const Size(400, 360), DolphinSignInExpired(onSignIn: noop));
    await _shot(tester, '27-side-strip', const Size(80, 200),
        Center(child: DolphinSideStrip(open: true, onToggle: noop, onScreenshot: noop, onKeyboard: (_) {})));
    await tester.pumpWidget(const SizedBox());
  }, skip: _dir == null);
  // Plan 18 Phase 4: health check, report, screenshot, stopped service, no monitor (customer x64).
  testWidgets('write phase 4 previews', (tester) async {
    await _loadFonts();
    // Real soft shadows under the dialogs (tests draw them solid by default).
    debugDisableShadows = false;
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    // As showDolphinPanel draws it: the light theme, over the dimmed window.
    Widget dialog(Widget child) => Container(
        color: Colors.black54,
        child: DolphinLight(
            paint: false,
            child: Center(
                child: Dialog(
                    insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: child)))));
    final checks = [
      serviceItem(installed: true, state: ServiceState.stopped, stopOption: false),
      registeredItem(true),
      dnsItem('remote.dolphindev.ir', isIp: false, addresses: ['185.143.233.133']),
      portItem('سرور دلفین', 21116, true),
      portItem('رله‌ی دلفین', 21117, false),
      portItem('پورتال دلفین', 443, true),
      diskItem(const []),
      displayItem(headless: false, installed: true, windowsBuild: 19045),
    ];
    await _shot(tester, '30-health-check', home, dialog(DolphinHealthView(
        items: checks, onFix: (_) {}, onSave: noop, onAgain: noop, onClose: noop,
        saved: 'گزارش روی دسکتاپ ذخیره شد:\n${healthReportName(DateTime(2026, 11, 13, 10, 30))}')));
    final note = TextEditingController(text: 'برنامه‌ی حسابداری باز نمی‌شود');
    await _shot(tester, '31-report-sent', home, dialog(DolphinUploadPanel(
        kind: UploadKind.diagnostics, phase: UploadPhase.done, note: note, onSend: noop, onClose: noop,
        message: uploadAnswer(200, '{"ok":true}').text)));
    // A made-up desktop: a taskbar and two windows.
    final screen = img.Image(width: 1280, height: 720)..clear(img.ColorRgb8(36, 99, 160));
    img.fillRect(screen, x1: 0, y1: 680, x2: 1280, y2: 720, color: img.ColorRgb8(30, 30, 40));
    img.fillRect(screen, x1: 120, y1: 90, x2: 760, y2: 520, color: img.ColorRgb8(245, 245, 245));
    img.fillRect(screen, x1: 120, y1: 90, x2: 760, y2: 120, color: img.ColorRgb8(20, 98, 224));
    img.fillRect(screen, x1: 640, y1: 260, x2: 1100, y2: 560, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(screen, x1: 660, y1: 300, x2: 1080, y2: 330, color: img.ColorRgb8(208, 60, 78));
    final png = Uint8List.fromList(img.encodePng(screen));
    // Decode it before the shot: a test frame does not wait for image codecs.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final ctx = tester.element(find.byType(SizedBox));
    await tester.runAsync(() => precacheImage(MemoryImage(png), ctx));
    await _shot(tester, '32-screenshot-confirm', home, dialog(DolphinUploadPanel(
        kind: UploadKind.screenshot, phase: UploadPhase.ready, note: TextEditingController(), png: png, onSend: noop, onClose: noop)));
    await _shot(tester, '33-service-stopped', home, DolphinHomeView(
        id: '123456789', state: DolphinServerState.stopped, onCopy: noop, onStartService: noop, phone: '021-44280505',
        siteLabel: 'support.dolphindev.ir', network: networkRows(server: DolphinServerState.stopped, localIp: '192.168.1.24'),
        version: '2.1.0'));
    await _shot(tester, '34-virtual-display', home, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: noop, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        headlessFix: headlessFix(installed: false, windowsBuild: 19045), network: net, version: '2.1.0'));
    await _shot(tester, '35-home-support-tools', homeTall, DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: noop, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        network: net, version: '2.1.0', onHealth: noop, onReport: noop, onScreenshot: noop, onStartHere: noop,
        onCopyDownload: noop, onCopyGuide: noop, onRequests: noop));
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }, skip: _dir == null);

  // Plan 18 Phase 4: «بررسی نسخه‌ی تازه» (DD-20) and the remote printer (DD-41).
  testWidgets('write install and update previews', (tester) async {
    await _loadFonts();
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    Widget about(Widget row) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DolphinAboutHeading(version: '2.0.0'),
          const SizedBox(height: 8),
          row,
        ]));
    await _shot(tester, '40-update-check', const Size(360, 200),
        about(DolphinUpdateCheckView(phase: UpdateCheckPhase.latest, onCheck: noop, onUpdate: noop)));
    await _shot(tester, '41-update-found', const Size(360, 200),
        about(DolphinUpdateCheckView(phase: UpdateCheckPhase.found, version: '2.1.0', onCheck: noop, onUpdate: noop)));
    await _shot(tester, '42-printer', const Size(360, 260), Padding(
        padding: const EdgeInsets.all(16),
        child: DolphinPrinterCard(
            ui: PrinterUi.printerMissing, mode: SwitchMode.available, printerName: 'DolphinConnect Printer', on: true,
            onInstall: noop, onChanged: (_) {})));
    final found = ManualUpdateCheck.fromJson('{"state":"update","version":"2.1.0","lead":"",'
        '"phone":"اگر درست نشد با پشتیبانی دلفین تماس بگیرید: ۰۲۱-۴۴۲۸۰۵۰۵","downloadPage":"https://support.dolphindev.ir/download"}');
    await _shot(tester, '43-update-dialog', const Size(460, 260), DolphinUpdateView(
        check: found.screen,
        progress: const DolphinUpdateProgress(state: 'downloading', percent: 40, text: '۹٫۸ از ۲۴٫۶ مگابایت'),
        currentVersion: '2.1.0-rc.1', framed: false,
        onRetry: noop, onDownloadPage: noop, onClose: noop, onContinue: noop));
    await tester.pumpWidget(const SizedBox());
  }, skip: _dir == null);
  // Plan 19: the update popup at every start (customer required, technician «به‌روزرسانی» / «بعداً») and a portal theme.
  testWidgets('write plan 19 previews', (tester) async {
    await _loadFonts();
    debugDisableShadows = false;
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    const customer = DolphinUpdateCheck(
        state: 'update',
        version: '2.1.0',
        lead: 'نسخه‌ی ۲.۱.۰ آماده است. پیش از باز شدن برنامه، نسخه‌ی تازه دریافت و جایگزین می‌شود.',
        phone: 'اگر درست نشد با پشتیبانی دلفین تماس بگیرید: ۰۲۱-۴۴۲۸۰۵۰۵');
    await _shot(tester, '80-update-popup-customer', const Size(500, 440), DolphinUpdateView(
        check: customer,
        progress: const DolphinUpdateProgress(state: 'downloading', percent: 48, text: '۱۲٫۰ از ۲۴٫۶ مگابایت'),
        currentVersion: '2.1.0-rc.1',
        onRetry: noop, onDownloadPage: noop, onClose: noop, onContinue: noop));
    const tech = DolphinUpdateCheck(
        state: 'manual',
        version: '2.1.0',
        lead: 'نسخه‌ی ۲.۱.۰ برنامه‌ی کارشناس آماده است. آن را از پنل دلفین دریافت کنید و به جای این برنامه اجرا کنید.',
        downloadPage: 'https://support.dolphindev.ir/staff/me');
    for (final (name, b) in [('81-update-popup-tech', Brightness.light), ('81-update-popup-tech-dark', Brightness.dark)]) {
      await tester.pumpWidget(const SizedBox()); // a new MaterialApp theme, not an animated change
      await _shot(tester, name, const Size(560, 360), Container(
          color: Colors.black.withOpacity(0.35),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: DolphinTechUpdatePopupView(check: tech, currentVersion: '2.1.0-rc.1', onUpdate: noop, onLater: noop)),
          theme: DolphinTechTheme.dataFor(b));
    }
    // A portal theme (`dolphin-theme`): green brand, smaller radii; the same customer home as 01.
    await tester.pumpWidget(const SizedBox());
    expect(applyThemeOverrides('{"v":1,"light":{"primary":"#0F5132","primaryText":"#0F5132","background":"#F4F8F5",'
            '"surfaceAlt":"#E6F2EA","accent":"#198754","success":"#0F5132","radius":6,"radiusLarge":10}}'),
        ThemeOverrideResult.applied);
    final now = DateTime.now();
    await _shot(tester, '82-theme-override', const Size(340, 900), DolphinHomeView(
        id: '123456789', state: DolphinServerState.ready, onCopy: noop, phone: '021-44280505', siteLabel: 'support.dolphindev.ir',
        network: networkRows(server: DolphinServerState.ready, localIp: '192.168.1.24'),
        recent: [RecentSession(now.subtract(const Duration(hours: 3)), 12, 'علی رضایی')],
        version: '2.1.0', onStartHere: noop, onCopyIp: noop, onCopyDownload: noop, onCopyGuide: noop,
        onRequests: noop, onCallback: noop));
    applyThemeOverrides(null);
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  }, skip: _dir == null);
  // Plan 18 Phase 5 (DD-11): Safe Mode restart and return.
  testWidgets('write safe mode previews', (tester) async {
    await _loadFonts();
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    final tech = DolphinTechTheme.dataFor(Brightness.light);
    Widget dialog(Widget child) => Center(
        child: Card(margin: const EdgeInsets.all(16), child: Padding(padding: const EdgeInsets.all(20), child: child)));
    await _shot(tester, '60-safe-mode-ask-tech', const Size(480, 300),
        dialog(DolphinSafeModeAskView(kind: DolphinRestartKind.safe, onConfirm: noop, onCancel: noop)), theme: tech);
    await _shot(tester, '61-safe-mode-notice', const Size(300, 380),
        DolphinRestartNoticeView(kind: DolphinRestartKind.safe, secondsLeft: 14, onCancel: noop));
    await _shot(tester, '62-safe-mode-banner', const Size(340, 520), Column(children: [
      DolphinSafeModeBanner(onReturn: noop),
      Expanded(child: DolphinHomeView(
          id: '123456789', state: DolphinServerState.ready, onCopy: noop, phone: '021-44280505',
          siteLabel: 'support.dolphindev.ir', network: networkRows(server: DolphinServerState.ready, localIp: '192.168.1.24'),
          version: '2.1.0')),
    ]));
    await _shot(tester, '63-safe-mode-answer-tech', const Size(480, 220), dialog(DolphinSafeModeAnswerView(
        answer: SafeModeAnswer(SafeModeTone.ok, safeModeAnswerFromMsgBox(kDolphinSafeModeKey, 'restarting-safe',
            'رایانه‌ی مشتری در حالت امن (با شبکه) دوباره راه‌اندازی می‌شود. پس از ورود مشتری به ویندوز، دلفین کانکت خودش باز می‌شود؛ آن وقت دوباره وصل شوید.')!.text),
        onClose: noop)), theme: tech);
    await _shot(tester, '64-safe-mode-return-confirm', const Size(340, 240),
        Center(child: DolphinSafeModeReturnConfirm(onConfirm: noop, onCancel: noop)));
    await _shot(tester, '65-safe-mode-notice-normal-zero', const Size(300, 380),
        DolphinRestartNoticeView(kind: DolphinRestartKind.normal, secondsLeft: 0, onCancel: noop));
    await _shot(tester, '66-toolbar-safe-mode', const Size(1000, 64), DolphinSessionBar(
        state: const DolphinBarState(latencyMs: 45, direct: true), onCtrlAltDel: noop, onLock: noop, onFiles: noop,
        onViewOnly: noop, onMyCursor: noop, onNoPicture: noop, onScreenshot: noop, onKeyboardLayout: noop,
        safeMode: DolphinRestartKind.normal, onSafeMode: (_) {}), theme: tech);
    await tester.pumpWidget(const SizedBox());
  }, skip: _dir == null);
  // Plan 18 Phase 6 (DD-31): «صدای رایانه‌ی مشتری» on the technician's toolbar.
  testWidgets('write phase 6 previews', (tester) async {
    await _loadFonts();
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    final tech = DolphinTechTheme.dataFor(Brightness.light);
    for (final (name, sound) in [
      ('70-toolbar-sound-off', DolphinSound.off),
      ('71-toolbar-sound-on', DolphinSound.on),
      ('72-sound-not-offered', DolphinSound.notOffered),
    ]) {
      await _shot(tester, name, const Size(1000, 64), DolphinSessionBar(
          state: const DolphinBarState(latencyMs: 45, direct: true), onCtrlAltDel: noop, onLock: noop, onFiles: noop,
          onViewOnly: noop, onMyCursor: noop, onNoPicture: noop, onScreenshot: noop, onKeyboardLayout: noop,
          sound: sound, onSound: noop), theme: tech);
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: _dir == null);
  // Plan 19 (D1–D2): «ارائه دمو».
  testWidgets('write demo previews', (tester) async {
    await _loadFonts();
    Directory(_dir!).createSync(recursive: true);
    void noop() {}
    final tech = DolphinTechTheme.dataFor(Brightness.light);
    Widget dialog(Widget child) => Center(
        child: Card(margin: const EdgeInsets.all(16), child: Padding(padding: const EdgeInsets.all(20), child: child)));
    await _shot(tester, '90-demo-tech-confirm', const Size(440, 300), dialog(DolphinDemoConfirmView(
        peerName: 'PC-RECEPTION', allScreens: false, onAllScreens: (_) {}, onStart: noop, onCancel: noop)), theme: tech);
    await _shot(tester, '91-demo-tech-bar', const Size(560, 44),
        DolphinDemoBar(peerName: 'PC-RECEPTION', elapsed: const Duration(minutes: 2, seconds: 14), onEnd: noop));
    await _shot(tester, '92-demo-customer-ask', const Size(300, 380), DolphinDemoAskView(
        technician: 'علی رضایی', canSee: true, secondsLeft: 52, phone: '021-44280505', onSee: noop, onNo: noop));
    // The window's own title bar is drawn by Windows; here a plain strip stands in for it, the picture a gradient.
    await _shot(tester, '93-demo-customer-window', const Size(640, 420), Column(children: [
      Container(
          height: 30,
          color: const Color(0xFFF0F4FB),
          alignment: Alignment.center,
          child: Text(demoWindowTitle('علی رضایی'),
              style: TextStyle(fontFamily: kDolphinFont, fontSize: 12, color: DolphinColors.muted))),
      Expanded(
          child: Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF2C4A7C), Color(0xFF4F7FBF), Color(0xFF9CC3E8)])))),
      DolphinDemoWindowBar(title: demoWindowTitle('علی رضایی'), screens: 2, current: 0, onScreen: (_) {}, onEnd: noop),
    ]));
    await tester.pumpWidget(const SizedBox());
  }, skip: _dir == null);
}
