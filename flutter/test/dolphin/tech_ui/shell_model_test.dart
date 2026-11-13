import 'dart:io';

import 'package:flutter_hbb/dolphin/tech/actions.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech_ui/settings_model.dart';
import 'package:flutter_hbb/dolphin/tech_ui/shell_model.dart';
import 'package:flutter_hbb/dolphin/theme_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  late FakePortal portal;
  late RecLauncher launcher;
  late FakePlatform platform;
  late AnswerPrompts prompts;
  late TechShellModel m;

  setUp(() async {
    portal = samplePortal();
    launcher = RecLauncher(recent: ['194052361']);
    platform = FakePlatform();
    prompts = AnswerPrompts();
    final s = servicesOn(portal, launcher: launcher);
    await signIn(s);
    m = TechShellModel(s, platform, prompts: prompts);
  });

  tearDown(() async {
    await shutDown(m);
    applyThemeOverrides(null);
  });

  test('start: reads the list, the queue, mine, the config; the portal\'s theme is applied; sign-out brings the built-in back',
      () async {
    portal.on('GET /config', (_) => configJson(theme: {'v': 1, 'light': {'primary': '#0b4fb8', 'primaryText': '#0b4fb8'}}));
    await m.start();
    await drain();
    expect(m.myId, '287654321');
    expect(m.dashboard.items.length, samplePcs.length);
    expect(m.requests.queueCount, 3);
    expect(m.myCalls.rows.single.subject, 'آموزش گزارش فروش');
    expect(m.config.callReasons.length, 4);
    expect(DolphinTheme.active.value.light.primary.value, 0xFF0B4FB8);
    expect(m.dashboard.recent.single.computer!.id, 'pc-1');
    await m.signOut();
    expect(DolphinTheme.active.value, DolphinThemeSet.builtIn);
    expect(m.dashboard.items, isEmpty);
    expect(portal.sent('POST /logout'), hasLength(1));
  });

  test('«اتصال»: the call is opened on the portal first, then the window; a notice says so', () async {
    await m.start();
    final o = await m.connect(const PcRef('pc-1', '194052361', 'پذیرش'));
    expect(o, isA<Connected>());
    expect(portal.body(portal.sent('POST /calls').single)['deviceId'], 'pc-1');
    expect(launcher.opened.single, ('194052361', null));
    expect(m.noticeOk, isTrue);
    expect(m.notice, contains('پذیرش'));
  });

  test('another technician holds the PC: asked, then taken over with takeover; «no» opens nothing', () async {
    await m.start();
    portal.onSeq('POST /calls', [
      (_) => FakePortal.error(409, 'in_session_other', 'در جلسه است', {'holderName': 'مریم احمدی'}),
      (_) => callJson,
    ]);
    await m.connect(const PcRef('pc-2', '305118742', 'ACC-02'));
    expect(prompts.takeoverAsked, ['مریم احمدی']);
    expect(portal.body(portal.sent('POST /calls').last)['takeover'], isTrue);
    expect(launcher.opened.single.$1, '305118742');

    prompts.takeover = false;
    portal.on('POST /calls', (_) => FakePortal.error(409, 'in_session_other', 'در جلسه است', {'holderName': 'مریم احمدی'}));
    final o = await m.connect(const PcRef('pc-2', '305118742', 'ACC-02'));
    expect(o, isA<HeldByOther>());
    expect(launcher.opened, hasLength(1));
  });

  test('a refusal shows the portal\'s Persian text; nothing opens', () async {
    await m.start();
    portal.on('POST /calls', (_) => FakePortal.error(403, 'not_linked', 'این رایانه به سازمانی وصل نیست.'));
    await m.connect(const PcRef('pc-1', '194052361'));
    expect(m.notice, 'این رایانه به سازمانی وصل نیست.');
    expect(m.noticeOk, isFalse);
    expect(launcher.opened, isEmpty);
  });

  test('portal away: «اتصال» opens the window without a call (TD-2), and says so', () async {
    await m.start();
    portal.on('GET /computers', (_) => throw const SocketException('down'));
    await m.dashboard.load();
    expect(m.offline, isTrue);
    expect(m.dashboard.offline, isTrue);
    expect(m.dashboard.items.length, samplePcs.length, reason: 'the cached list');
    portal.requests.clear();
    await m.connect(const PcRef('pc-1', '194052361'));
    expect(portal.sent('POST /calls'), isEmpty);
    expect(launcher.opened.single.$1, '194052361');
    expect(m.notice, kMsgOfflineOpened);
  });

  test('the header\'s ID field finds the PC on the portal; an unknown ID is said; a bad one too', () async {
    await m.start();
    portal.on('GET /computers', (req) {
      final q = req.url.queryParameters['q'];
      return computersPage(q == null ? samplePcs : samplePcs.where((p) => p['rustdeskId'] == q).toList());
    });
    await m.connectTyped('۴۱۲ ۷۰۰ ۹۱۳');
    expect(portal.body(portal.sent('POST /calls').single)['deviceId'], 'pc-3');
    await m.connectTyped('999 999 999');
    expect(m.notice, kMsgIdNotInList);
    await m.connectTyped('12');
    expect(m.notice, kMsgIdFormat);
    expect(launcher.opened, hasLength(1));
  });

  test('«ارائه دمو» without the demo part: authorized on the portal, then says the window did not open', () async {
    await m.start();
    final o = await m.connect(const PcRef('pc-1', '194052361'), demo: true);
    expect(o, isA<LaunchFailed>());
    expect(portal.sent('POST /demo'), hasLength(1));
    expect(m.notice, kMsgDemoNotOpened);
  });

  group('«ارائه دمو» through demo_hooks', () {
    late List<(String, bool)> opened;
    late TechShellModel dm;
    setUp(() async {
      opened = [];
      final s = servicesOn(portal, launcher: launcher, demo: TechDemoStarter((id, all) async => opened.add((id, all))));
      await signIn(s);
      dm = TechShellModel(s, platform, prompts: prompts);
      await dm.start();
    });
    tearDown(() => shutDown(dm));

    test('confirmed with all screens: the portal authorizes first (POST /demo), then the demo session opens', () async {
      prompts.demoAnswer = true;
      final o = await dm.connect(const PcRef('pc-1', '194052361', 'پذیرش'), demo: true);
      expect(prompts.demoAsked, ['پذیرش']);
      expect(o, isA<Connected>());
      expect(portal.body(portal.sent('POST /demo').single)['deviceId'], 'pc-1');
      expect(opened, [('194052361', true)]);
      expect(launcher.opened, isEmpty, reason: 'no control session');
    });

    test('cancelled at D1: nothing reaches the portal, nothing opens', () async {
      prompts.demoAnswer = null;
      expect(await dm.connect(const PcRef('pc-1', '194052361'), demo: true), isNull);
      expect(portal.sent('POST /demo'), isEmpty);
      expect(opened, isEmpty);
    });

    test('the portal refuses: its Persian text, and no session', () async {
      portal.on('POST /demo', (_) => FakePortal.error(403, 'forbidden', 'دمو برای این سازمان بسته است.'));
      await dm.connect(const PcRef('pc-1', '194052361'), demo: true);
      expect(dm.notice, 'دمو برای این سازمان بسته است.');
      expect(opened, isEmpty);
    });
  });

  test('code mode: «اتصال» opens the card and waits for the code instead of a window', () async {
    await m.start();
    portal.on('POST /calls', (_) => {...callJson, 'consentMode': 'code', 'waiting': true, 'authorizedUntil': null});
    final o = await m.connect(const PcRef('pc-1', '194052361'));
    expect(o, isA<WaitingForCode>());
    expect(launcher.opened, isEmpty);
    expect(m.cardId, 'pc-1');
  });

  test('«برداشتن و تماس»: takes the request, then connects to its PC', () async {
    await m.start();
    await drain();
    portal.on('POST /requests/q-1/take', (_) => {'ok': true});
    await m.takeAndCall(m.requests.rows.first);
    expect(portal.sent('POST /requests/q-1/take'), hasLength(1));
    expect(portal.body(portal.sent('POST /calls').single)['deviceId'], 'pc-2');
  });

  test('notifications: the first answer is listed, never a toast; later ones toast when the app is not in front', () async {
    portal.onSeq('GET /notifications', [
      (_) => [note('n1', 'request', 'درخواست تازه در صف', 'چاپگر فاکتور · گردش‌کار')],
      (_) => [note('n2', 'callback', '«با من تماس بگیرید»', 'ACC-02 · پارس‌کار', deviceId: 'pc-2')],
      (_) => [note('n3', 'request', 'درخواست تازه', 'نیک‌خودرو')],
    ]);
    await m.start();
    await drain();
    expect(m.notifications.items.map((n) => n.id), ['n1']);
    expect(platform.toasts, isEmpty);
    expect(m.toast, isNull);

    platform.inFront = false;
    await m.services.poller.poll();
    await drain();
    expect(m.notifications.unread, 2);
    expect(platform.toasts.single, '«با من تماس بگیرید» — ACC-02 · پارس‌کار');
    expect(m.toast!.id, 'n2');
    m.openNotification(m.toast!);
    expect(m.cardId, 'pc-2');
    expect(m.toast, isNull);

    await m.setToasts(false);
    expect(m.services.prefs.get(kTechToastsPref), 'N');
    await m.services.poller.poll();
    await drain();
    expect(platform.toasts, hasLength(1), reason: 'toasts turned off');
    m.toggleBell();
    expect(m.bellUnread, 3);
    expect(m.notifications.unread, 0);
  });

  test('RO-8: a session window that closes on a PC with this technician\'s open call offers the end step', () async {
    await m.start();
    await m.connect(const PcRef('pc-1', '194052361', 'پذیرش'));
    platform.sessions.update(['194052361'], DateTime.now());
    portal.on('GET /computers/pc-1', (_) => detailJson(samplePcs.first, call: callJson2()));
    platform.sessions.update([], DateTime.now());
    await drain();
    expect(prompts.endAsked.single.$1.deviceId, 'pc-1');
    expect(prompts.endAsked.single.$2.requestId, 'call-1');

    portal.on('POST /calls/call-1/end', (_) => {'ok': true});
    expect(await m.endCall('call-1', reasonId: 'install', note: 'برنامه نصب شد'), isNull);
    expect(portal.body(portal.sent('POST /calls/call-1/end').single), {'reasonId': 'install', 'note': 'برنامه نصب شد'});
  });

  test('a session closing without an open call asks nothing; one not opened here is ignored', () async {
    await m.start();
    await m.connect(const PcRef('pc-3', '412700913'));
    platform.sessions.update(['412700913', '111111111'], DateTime.now());
    platform.sessions.update([], DateTime.now());
    await drain();
    expect(prompts.endAsked, isEmpty);
  });

  test('settings write upstream\'s own options; «بازنشانی این بخش» puts the defaults back', () async {
    final s = m.settings;
    await s.setViewStyle('adaptive');
    await s.setSwitch(kDisplaySwitches.first, true);
    await s.setSwitch(kDisplaySwitches.last, true);
    await s.setSwitch(kInputSwitches.first, true);
    expect(platform.settings.user[kViewStyleKey], 'adaptive');
    expect(platform.settings.user[kZoomCursorKey], 'Y');
    expect(platform.settings.local[kOpenInTabsKey], isTrue);
    expect(platform.settings.user[kSwapMouseKey], 'Y');
    await s.reset(TechSettingsSection.display);
    expect(platform.settings.user[kViewStyleKey], 'original');
    expect(platform.settings.user[kZoomCursorKey], 'N');
    expect(platform.settings.local[kOpenInTabsKey], isFalse);
    expect(platform.settings.user[kSwapMouseKey], 'Y', reason: 'another section');
    await s.reset(TechSettingsSection.input);
    expect(platform.settings.user[kSwapMouseKey], 'N');
    expect(platform.settings.user.containsKey(kImageQualityKey), isFalse, reason: 'quality is never written');
  });

  test('«دریافت»: a sent file comes down with the staff token into the downloads folder', () async {
    await m.start();
    portal.on('GET /reports/sent-1', (_) => FakePortal.json('png'));
    final item = SentItem('sent-1', 'screenshot', 5, null, DateTime.now(), '/api/app/v1/reports/sent-1');
    await m.downloadSent(item);
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}dolphin-screenshot-sent-1.png');
    expect(file.existsSync(), isTrue);
    expect(portal.sent('GET /reports/sent-1').single.headers['Authorization'], 'Bearer tok-secret-123');
    file.deleteSync();
  });
}
