import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/no_picture.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/state.dart';
import 'package:flutter_hbb/dolphin/tech_ui/dashboard.dart';
import 'package:flutter_hbb/dolphin/tech_ui/notifications.dart';
import 'package:flutter_hbb/dolphin/tech_ui/pc_card.dart';
import 'package:flutter_hbb/dolphin/tech_ui/platform.dart';
import 'package:flutter_hbb/dolphin/tech_ui/requests.dart';
import 'package:flutter_hbb/dolphin/tech_ui/sections.dart';
import 'package:flutter_hbb/dolphin/tech_ui/settings_model.dart';
import 'package:flutter_hbb/dolphin/tech_ui/settings_view.dart';
import 'package:flutter_hbb/dolphin/tech_ui/shell.dart';
import 'package:flutter_hbb/dolphin/tech_ui/shell_model.dart';
import 'package:flutter_hbb/dolphin/tech_ui/signin.dart';
import 'package:flutter_test/flutter_test.dart';

import '../contrast.dart';
import 'harness.dart';

/// Widget tests of the native technician screens (T1–T7, sign-in, RO-8): each state, both themes readable.
void main() {
  void big(WidgetTester tester) {
    // The test font's glyphs are wide (Ahem); the real window is 1120 × 720 with Vazirmatn (see the previews).
    tester.view.physicalSize = const Size(2600, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<TechShellModel> model(WidgetTester tester, FakePortal portal,
      {Prefs? prefs, bool signedIn = true, FakePlatform? platform, RecLauncher? launcher}) async {
    late TechShellModel m;
    await tester.runAsync(() async {
      final s = servicesOn(portal, prefs: prefs, launcher: launcher);
      if (signedIn) {
        await signIn(s);
      } else {
        await s.session.load();
      }
      m = TechShellModel(s, platform ?? FakePlatform(), prompts: AnswerPrompts());
      if (signedIn) {
        await m.start();
        await drain(20);
      }
    });
    return m;
  }

  Future<void> close(WidgetTester tester, TechShellModel m) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => shutDown(m));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => drain(20));
    await tester.pump();
  }

  group('sign-in (ADR-0008)', () {
    testWidgets('signed out: username and password only; a wrong password shows the portal\'s text', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('POST /login', (_) => FakePortal.error(401, 'invalid', 'نام کاربری یا رمز عبور درست نیست.'));
      final m = await model(tester, portal, signedIn: false);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await tester.pump();
      expect(find.byType(TechSignInView), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2), reason: 'no second step, no SMS');
      expect(find.byKey(const ValueKey('tech-signin-expired')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('tech-signin-user')), 'ali.rezaei');
      await tester.enterText(find.byKey(const ValueKey('tech-signin-pass')), 'wrong-password');
      await tester.tap(find.byKey(const ValueKey('tech-signin-submit')));
      await settle(tester);
      expect(find.text('نام کاربری یا رمز عبور درست نیست.'), findsOneWidget);
      final pass = tester.widget<TextField>(find.byKey(const ValueKey('tech-signin-pass')));
      expect(pass.controller!.text, isEmpty, reason: 'the password is never kept');
      expectAllTextReadable(tester);
      await close(tester, m);
    });

    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('expired ($name): «ورود منقضی شد» over the form, readable', (tester) async {
        big(tester);
        final m = await model(tester, samplePortal(), signedIn: false);
        await tester.pumpWidget(app(TechSignInView(session: m.services.session, expired: true)));
        expect(find.byKey(const ValueKey('tech-signin-expired')), findsOneWidget);
        expect(find.text('ورود منقضی شد'), findsOneWidget);
        expectAllTextReadable(tester);
        await close(tester, m);
      });
    }

    testWidgets('a 401 expired mid-use brings the expired sign-in back', (tester) async {
      big(tester);
      final portal = samplePortal();
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await tester.pump();
      expect(find.byType(TechDashboard), findsOneWidget);
      portal.on('GET /computers', (_) => FakePortal.error(401, 'expired', 'ورود شما تمام شده است.'));
      await tester.runAsync(() => m.dashboard.load());
      await settle(tester);
      expect(find.byKey(const ValueKey('tech-signin-expired')), findsOneWidget);
      await close(tester, m);
    });
  });

  group('T1 «رایانه‌ها»', () {
    testWidgets('tiles are the default; the list choice is remembered for the next start', (tester) async {
      big(tester);
      final prefs = MemoryPrefs();
      var m = await model(tester, samplePortal(), prefs: prefs);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await tester.pump();
      expect(find.byKey(const ValueKey('pc-tiles')), findsOneWidget);
      expect(find.byType(PcTile), findsNWidgets(samplePcs.length));
      expect(find.text('۱۹۴ ۰۵۲ ۳۶۱'), findsOneWidget, reason: 'ID in Persian digits, grouped');
      await tester.tap(find.byKey(const ValueKey('view-list')));
      await tester.pump();
      expect(find.byKey(const ValueKey('pc-list')), findsOneWidget);
      expect(prefs.get(kTechViewModeOption), 'list');
      await close(tester, m);

      m = await model(tester, samplePortal(), prefs: prefs);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await tester.pump();
      expect(find.byKey(const ValueKey('pc-list')), findsOneWidget);
      await close(tester, m);
    });

    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('the window ($name): header, navigation, tiles and bottom bar read at AA', (tester) async {
        big(tester);
        final platform = FakePlatform();
        final m = await model(tester, samplePortal(), platform: platform);
        platform.sessions.update(['194052361'], DateTime.now().subtract(const Duration(minutes: 7)));
        await tester.pumpWidget(app(TechShell(model: m)));
        await tester.pump();
        expect(find.text('دلفین کانکت کارشناس'), findsOneWidget);
        expect(find.text('علی رضایی'), findsOneWidget);
        expect(find.byKey(const ValueKey('session-194052361')), findsOneWidget);
        expect(find.text('سرور دلفین: وصل'), findsOneWidget);
        expectAllTextReadable(tester);
        await tester.tap(find.byKey(const ValueKey('view-list')));
        await tester.pump();
        expectAllTextReadable(tester);
        await tester.tap(find.byKey(const ValueKey('session-194052361')));
        expect(platform.focused, ['194052361']);
        await close(tester, m);
      });
    }

    testWidgets('loading, then empty with filters offers to drop them; an error offers a retry', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('GET /computers', (_) => computersPage(const []));
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await tester.pump();
      expect(find.text('هنوز رایانه‌ای به دلفین وصل نشده است.'), findsOneWidget);
      m.dashboard.setView(PcView.favorite);
      await settle(tester);
      expect(find.text('برداشتن فیلترها'), findsOneWidget);
      portal.on('GET /computers', (_) => FakePortal.error(500, 'server', 'خطای سرور؛ چند لحظه بعد دوباره امتحان کنید.'));
      await tester.runAsync(() => m.dashboard.load());
      await settle(tester);
      expect(find.text('خطای سرور؛ چند لحظه بعد دوباره امتحان کنید.'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);
      await close(tester, m);
    });

    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('T5 portal away ($name): amber card with the reason, the cached list read-only, connect by ID works',
          (tester) async {
        big(tester);
        final portal = samplePortal();
        final launcher = RecLauncher();
        final m = await model(tester, portal, launcher: launcher);
        portal.on('GET /computers', (_) => throw const SocketException('refused'));
        await tester.runAsync(() => m.dashboard.load());
        await tester.pumpWidget(app(TechShell(model: m)));
        await settle(tester);
        expect(find.byKey(const ValueKey('tech-offline-card')), findsOneWidget);
        expect(find.text(TechOfflineCard.title), findsOneWidget);
        expect(find.textContaining('آخرین وضعیت: ساعت'), findsOneWidget);
        expect(find.textContaining('اینترنت این رایانه وصل است ولی پورتال جواب نمی‌دهد.'), findsOneWidget);
        expect(find.text('پورتال: در دسترس نیست'), findsOneWidget);
        expect(find.byType(PcTile), findsNWidgets(samplePcs.length));
        expectAllTextReadable(tester);
        await tester.enterText(find.byKey(const ValueKey('tech-id-field')), '412 700 913');
        await tester.tap(find.byKey(const ValueKey('tech-connect')));
        await settle(tester);
        expect(launcher.opened.single.$1, '412700913');
        expect(portal.sent('POST /calls'), isEmpty);
        await close(tester, m);
      });
    }
  });

  group('T2 the card', () {
    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('open call ($name): reasons, note, message, end; sent files and history; readable', (tester) async {
        big(tester);
        final portal = samplePortal();
        portal.on('GET /computers/pc-1', (_) => detailJson(samplePcs.first, call: callJson2(live: true)));
        final m = await model(tester, portal);
        await tester.pumpWidget(app(TechShell(model: m)));
        m.openCard('pc-1');
        await settle(tester);
        expect(find.byKey(const ValueKey('tech-pc-card')), findsOneWidget);
        expect(find.text('تماس باز'), findsOneWidget);
        expect(find.text('نصب برنامه'), findsOneWidget);
        expect(find.text('فرستاده‌ی مشتری'), findsOneWidget);
        expect(find.textContaining('این پیام خطا می‌آید'), findsOneWidget);
        expect(find.text('آخرین تماس‌ها'), findsOneWidget);
        expectAllTextReadable(tester);
        portal.on('POST /calls/call-1/reason', (_) => {'ok': true});
        await tester.tap(find.byKey(const ValueKey('reason-error')));
        await settle(tester);
        expect(portal.body(portal.sent('POST /calls/call-1/reason').single), {'reasonId': 'error'});
        await tester.tap(find.byKey(const ValueKey('tech-card-close')));
        await tester.pump();
        expect(find.byKey(const ValueKey('tech-pc-card')), findsNothing);
        await close(tester, m);
      });
    }

    testWidgets('RO-8 from the card: «پایان تماس» with a reason and a note; «بعداً» closes nothing', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('GET /computers/pc-1', (_) => detailJson(samplePcs.first, call: callJson2()));
      portal.on('POST /calls/call-1/end', (_) => {'ok': true});
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      m.openCard('pc-1');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tech-card-end')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tech-end-of-call')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('end-later')));
      await tester.pumpAndSettle();
      expect(portal.sent('POST /calls/call-1/end'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('tech-card-end')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('end-reason-training')));
      await tester.enterText(find.byKey(const ValueKey('end-note')), 'آموزش گزارش فروش داده شد');
      await tester.tap(find.byKey(const ValueKey('end-confirm')));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(portal.body(portal.sent('POST /calls/call-1/end').single),
          {'reasonId': 'training', 'note': 'آموزش گزارش فروش داده شد'});
      expect(find.byKey(const ValueKey('tech-end-of-call')), findsNothing);
      await close(tester, m);
    });

    testWidgets('a card that fails to load says why and offers a retry', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('GET /computers/pc-1', (_) => FakePortal.error(404, 'not_found', 'این رایانه پیدا نشد.'));
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      m.openCard('pc-1');
      await settle(tester);
      expect(find.text('این رایانه پیدا نشد.'), findsOneWidget);
      expect(find.text('تلاش دوباره'), findsOneWidget);
      await close(tester, m);
    });
  });

  group('T3 requests', () {
    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('queue ($name): waiting time amber once old; «برداشتن و تماس»; readable', (tester) async {
        big(tester);
        final portal = samplePortal();
        portal.on('POST /requests/q-1/take', (_) => {'ok': true});
        final m = await model(tester, portal);
        await tester.pumpWidget(app(TechShell(model: m)));
        await tester.tap(find.byKey(const ValueKey('nav-requests')));
        await settle(tester);
        expect(find.byType(TechRequestsView), findsOneWidget);
        expect(find.text('برنامه باز نمی‌شود'), findsOneWidget);
        expect(find.text('«با من تماس بگیرید» از برنامه', findRichText: true), findsNothing);
        expect(find.textContaining('«با من تماس بگیرید» از برنامه'), findsOneWidget);
        final old = tester.widget<Container>(find.byKey(const ValueKey('wait-q-1')));
        final fresh = tester.widget<Container>(find.byKey(const ValueKey('wait-q-2')));
        expect((old.decoration as BoxDecoration).color, isNot((fresh.decoration as BoxDecoration).color));
        expectAllTextReadable(tester);
        await tester.tap(find.byKey(const ValueKey('take-q-1')));
        await settle(tester);
        expect(portal.sent('POST /requests/q-1/take'), hasLength(1));
        expect(portal.body(portal.sent('POST /calls').single)['deviceId'], 'pc-2');
        await close(tester, m);
      });
    }

    testWidgets('an empty queue says so; «تماس‌های من» lists mine', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('GET /requests', (req) => req.url.queryParameters['scope'] == 'mine'
          ? requestsPage([request('m-1', 1039, 'آموزش گزارش فروش', orgGardesh, mine: true, deviceId: 'pc-1', rid: '194052361')])
          : requestsPage([], queue: 0));
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await tester.tap(find.byKey(const ValueKey('nav-requests')));
      await settle(tester);
      expect(find.text('صف خالی است؛ درخواستی منتظر نیست.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('nav-myCalls')));
      await settle(tester);
      expect(find.text('آموزش گزارش فروش'), findsOneWidget);
      await close(tester, m);
    });
  });

  group('T4 notifications', () {
    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('bell list and in-app notice ($name) read at AA; empty says so', (tester) async {
        big(tester);
        final items = [
          AppNotification(
              id: 'a', kind: NotificationKind.callback, title: '«با من تماس بگیرید»', body: 'ACC-02 · پارس‌کار', deviceId: 'pc-2', at: DateTime.now()),
          AppNotification(id: 'b', kind: NotificationKind.request, title: 'درخواست تازه در صف', body: 'نیک‌خودرو', at: DateTime.now()),
        ];
        AppNotification? opened;
        await tester.pumpWidget(app(Column(children: [
          TechNotificationsPanel(items: items, unreadBefore: 1, onOpen: (n) => opened = n, onClose: () {}),
          const SizedBox(height: 12),
          TechToastCard(item: items.first, onOpen: () {}, onLater: () {}),
          const SizedBox(height: 12),
          TechNotificationsPanel(items: const [], onOpen: (_) {}, onClose: () {}),
        ])));
        expect(find.text('اعلان تازه‌ای نیست.'), findsOneWidget);
        expect(find.text('تماس'), findsOneWidget);
        expectAllTextReadable(tester);
        await tester.tap(find.byKey(const ValueKey('notification-b')));
        expect(opened!.id, 'b');
      });
    }

    testWidgets('the bell shows the unread count and opens the list', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('GET /notifications', (_) => [note('n1', 'request', 'درخواست تازه در صف', 'چاپگر فاکتور')]);
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      await settle(tester);
      expect(find.text('۱'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('tech-bell')));
      await tester.pump();
      expect(find.byKey(const ValueKey('tech-notifications')), findsOneWidget);
      expect(find.text('درخواست تازه در صف'), findsOneWidget);
      await close(tester, m);
    });
  });

  group('T6 settings', () {
    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('every section ($name): title, subtitle, reset; readable', (tester) async {
        big(tester);
        final store = MemorySettingsStore();
        final model = TechSettingsModel(store);
        var theme = ThemeMode.dark;
        var view = PcViewMode.list;
        var toasts = false;
        await tester.pumpWidget(app(StatefulBuilder(
          builder: (context, setState) => TechSettingsView(
            model: model,
            themeMode: theme,
            onThemeMode: (t) => setState(() => theme = t),
            viewMode: view,
            onViewMode: (v) => setState(() => view = v),
            toasts: toasts,
            onToasts: (v) => setState(() => toasts = v),
            downloadsPath: r'C:\Users\ali\Downloads\Dolphin Connect',
            portalUrl: 'https://support.dolphindev.ir',
            serverOnline: true,
            version: '2.1.0',
          ),
        )));
        for (final s in TechSettingsSection.values) {
          await tester.tap(find.byKey(ValueKey('settings-${s.name}')));
          await tester.pump();
          expect(find.text(sectionSubtitle(s)), findsOneWidget);
          expect(find.text(kResetSection), findsOneWidget);
          expectAllTextReadable(tester);
        }
        await tester.tap(find.byKey(const ValueKey('settings-display')));
        await tester.pump();
        expect(find.text('خودکار (پیشنهادی)'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('switch-$kOpenInTabsKey')));
        await tester.pump();
        expect(store.local[kOpenInTabsKey], isTrue);
        await tester.tap(find.byKey(const ValueKey('settings-look')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('settings-reset')));
        await tester.pump();
        expect(theme, ThemeMode.system);
        expect(view, PcViewMode.tiles);
        await tester.tap(find.byKey(const ValueKey('settings-sound')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('settings-reset')));
        await tester.pump();
        expect(toasts, isTrue);
      });
    }
  });

  group('T7 stages', () {
    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('named stages, then after 60 s the network line with three choices ($name)', (tester) async {
        var cad = 0, closed = 0;
        await tester.pumpWidget(app(Center(
            child: AlertDialog(
                content: SizedBox(
                    width: 460,
                    child: DolphinWaitingForPicture(
                        waiting: const Text('وصل شد؛ در انتظار تصویر…'),
                        peer: 'PC-RECEPTION',
                        canCtrlAltDel: true,
                        onCtrlAltDel: () => cad++,
                        onDisconnect: () => closed++))))));
        expect(find.text(kStageSecure), findsOneWidget);
        expect(find.text('در انتظار تصویر از PC-RECEPTION'), findsOneWidget);
        expectAllTextReadable(tester);
        await tester.pump(const Duration(seconds: 61));
        expect(find.byKey(const ValueKey('dolphin-slow-picture')), findsOneWidget);
        expect(find.text(kSlowPictureText), findsOneWidget);
        expectAllTextReadable(tester);
        await tester.tap(find.text(kSlowSendCad));
        expect(cad, 1);
        await tester.tap(find.text(kSlowKeepWaiting));
        await tester.pump();
        expect(find.byKey(const ValueKey('dolphin-slow-picture')), findsNothing);
        await tester.pump(const Duration(seconds: 61));
        await tester.tap(find.text(kNoPictureDisconnect));
        expect(closed, 1);
      });
    }
  });

  group('RO-8 view and the code box', () {
    for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
      testWidgets('the end-of-call view ($name) reads at AA and reports the choice', (tester) async {
        (String?, String?)? got;
        await tester.pumpWidget(app(Center(
          child: TechEndOfCallView(
            pcName: 'PC-RECEPTION',
            reasons: const [CallReason('install', 'نصب برنامه'), CallReason('error', 'رفع خطا')],
            onEnd: (r, n) async {
              got = (r, n);
              return true;
            },
            onLater: () {},
          ),
        )));
        expectAllTextReadable(tester);
        await tester.tap(find.byKey(const ValueKey('end-reason-error')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('end-confirm')));
        await tester.pump();
        expect(got, ('error', null));
      });
    }

    testWidgets('code mode in the card: «در انتظار کد مشتری…» and a code field', (tester) async {
      big(tester);
      final portal = samplePortal();
      portal.on('GET /computers/pc-1', (_) => detailJson(samplePcs.first, call: callJson2(consent: 'code', waitingForCode: true)));
      final m = await model(tester, portal);
      await tester.pumpWidget(lightApp(TechShell(model: m)));
      m.openCard('pc-1');
      await settle(tester);
      expect(find.text(kWaitingForCode), findsOneWidget);
      expect(find.byKey(const ValueKey('tech-card-code-field')), findsOneWidget);
      expectAllTextReadable(tester);
      m.closeCard();
      await tester.pump();
      await close(tester, m);
    });
  });

  testWidgets('sections: organizations, history and snippets show their lists', (tester) async {
    big(tester);
    final platform = FakePlatform();
    final portal = samplePortal();
    portal.on('GET /history', (_) => {'rows': (detailJson(samplePcs.first)['history'] as List)});
    final m = await model(tester, portal, platform: platform);
    await tester.pumpWidget(lightApp(TechShell(model: m)));
    await tester.tap(find.byKey(const ValueKey('nav-organizations')));
    await settle(tester);
    expect(find.text('پارس‌کار'), findsWidgets);
    await tester.tap(find.byKey(ValueKey('org-${orgGardesh['id']}')));
    await settle(tester);
    portal.on('GET /organizations/${orgGardesh['id']}', (_) => {
          'organization': {...orgGardesh, 'consentMode': 'click', 'active': true, 'fixedPassword': true},
          'customers': [],
        });
    await tester.tap(find.byKey(const ValueKey('nav-snippets')));
    await settle(tester);
    expect(find.text('مسیر پشتیبان‌گیری'), findsOneWidget);
    await tester.tap(find.text('کپی').first);
    await tester.pump();
    expect(platform.copies.single, 'پشتیبانی دلفین: ۰۲۱-۴۴۲۸۰۵۰۵');
    await tester.tap(find.byKey(const ValueKey('nav-history')));
    await settle(tester);
    expect(find.textContaining('یک سازمان را انتخاب کنید'), findsOneWidget);
    await tester.runAsync(() => m.history.show(m.organizations.rows.first));
    await settle(tester);
    expect(find.textContaining('تماس تلفنی'), findsOneWidget);
    await close(tester, m);
  });

  testWidgets('the card\'s «اتصال» goes through the portal and opens the window', (tester) async {
    big(tester);
    final portal = samplePortal();
    final launcher = RecLauncher();
    final m = await model(tester, portal, launcher: launcher);
    await tester.pumpWidget(lightApp(TechShell(model: m)));
    m.openCard('pc-1');
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('tech-card-connect')));
    await settle(tester);
    expect(portal.sent('POST /calls'), hasLength(1));
    expect(launcher.opened.single.$1, '194052361');
    expect(find.byType(TechPcCard), findsOneWidget);
    await close(tester, m);
  });
}
