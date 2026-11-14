
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/customer_api/api.dart';
import 'package:flutter_hbb/dolphin/customer_api/session.dart';
import 'package:flutter_hbb/dolphin/customer_requests.dart';
import 'package:flutter_hbb/dolphin/customer_ui/format.dart';
import 'package:flutter_hbb/dolphin/customer_ui/views.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'contrast.dart';
import 'customer_api_test.dart' show customerJson, detailJson, loginJson, reqId, rowJson;
import 'tech/fake_portal.dart' show FakePortal, FixedProbe;

// Plan 19 C4: the customer app's native «درخواست‌ها و پیام‌ها» (C4.1–C4.6) on a scripted portal: the flows, the consent
// rules in both modes, sign-out and expiry, the window sizes, and AA contrast in the customer's light and dark.

const kCode = 'Zq7Wx3Kp';
const kPcId = '123456789';

/// The window's content at 460 × 640 and at the minimum window (360 × 540), less upstream's title bar (home.dart).
const kWindow = Size(449, 602);
const kMinimum = Size(349, 502);

class Harness {
  final FakePortal portal = FakePortal();
  late final CustomerApi api = CustomerApi(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe());
  final MemoryBox box = MemoryBox();
  late final CustomerSession session = CustomerSession(api, box);
  int codeReads = 0;
  bool local = true;
  int shots = 0;
  bool backed = false;

  String readCode() {
    codeReads++;
    return kCode;
  }

  Harness({String consentMode = 'code', bool mustChange = false}) {
    portal.on('POST /customer/login', (_) => loginJson(mustChange: mustChange));
    portal.on('POST /customer/logout', (_) => {'ok': true});
    portal.on('GET /customer/me', (_) => {'customer': customerJson(), 'mustChangePassword': mustChange});
    portal.on('GET /customer/unread', (_) => {'count': 1});
    portal.on(
        'GET /customer/products',
        (_) => [
              {'id': 'p1', 'name': 'نرم‌افزار حسابداری'}
            ]);
    portal.on(
        'GET /customer/requests',
        (req) => {
              'rows': req.url.queryParameters['scope'] == 'closed'
                  ? [rowJson(id: 'closed-1', status: 'resolved', unread: false)]
                  : [rowJson(), rowJson(id: 'r2', status: 'submitted', unread: false, product: 'فروشگاهی')]
            });
    portal.on('GET /customer/requests/$reqId', (_) => detailJson(consentMode: consentMode));
    portal.on('POST /customer/requests/$reqId/device', (_) => {'ok': true, 'message': 'ثبت شد.'});
    portal.on('POST /customer/requests/$reqId/messages', (_) => {'ok': true});
    portal.on('POST /customer/requests', (_) => {'id': reqId, 'number': 125});
  }

  Widget app({bool connectedNow = false, Size? size}) => MaterialApp(
        theme: dolphinTheme(ThemeData.light()),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: DolphinCustomerRequests(
              session: session,
              id: kPcId,
              readCode: readCode,
              connectedNow: connectedNow,
              pressIsLocal: () async => local,
              takeScreenshot: () async {
                shots++;
                return Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 6)));
              },
              pickFile: () async => null,
              saveAs: (_) async => null,
              phone: '021-44280505',
              onBack: () => backed = true,
              refreshEvery: null,
              now: () => DateTime.utc(2026, 11, 14, 9),
            ),
          ),
        ),
      );
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> at(WidgetTester tester, Size size, Widget child, {bool dark = false}) async {
  DolphinCustomerTheme.apply(dark ? DolphinThemeChoice.dark : DolphinThemeChoice.light, platform: Brightness.light);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await settle(tester);
}

Future<void> signIn(WidgetTester tester, Harness h) async {
  await tester.enterText(find.byKey(const ValueKey('c4-username')), 'parskar.reception');
  await tester.enterText(find.byKey(const ValueKey('c4-password')), 'pass-word-1');
  await tester.tap(find.byKey(const ValueKey('c4-signin')));
  await settle(tester);
}

Future<void> openRequest(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('c4-row-$reqId')));
  await settle(tester);
}

/// Every text the screen shows or holds: Text, rich text, fields.
String screenText(WidgetTester tester) {
  final out = StringBuffer();
  for (final e in find.byType(RichText).evaluate()) {
    out.writeln((e.widget as RichText).text.toPlainText());
  }
  for (final e in find.byType(EditableText).evaluate()) {
    out.writeln((e.widget as EditableText).controller.text);
  }
  return out.toString();
}

void main() {
  tearDown(DolphinCustomerTheme.reset);

  group('format (pure)', () {
    final now = DateTime(2026, 11, 14, 12);
    test('the statuses read as the design draws them', () {
      expect(statusLabel('submitted'), 'در صف');
      expect(statusLabel('claimed'), 'در حال بررسی');
      expect(statusLabel('resolved'), 'حل‌شده');
      expect(statusTone('in_session'), StatusTone.active);
    });

    test('a row\'s lines: number and product, then the last message or «ثبت شد»', () {
      final r = CustomerRequestRow.fromJson(rowJson());
      expect(metaLine(r), '#۱۲۴ · حسابداری');
      expect(lastLine(r, DateTime.utc(2026, 11, 14, 9)), startsWith('علی رضایی: «ساعت ۱۱ وصل می‌شوم…» · '));
      final quiet = CustomerRequestRow(id: 'x', number: 7, subject: 's', status: 'submitted', updatedAt: now);
      expect(lastLine(quiet, now), 'ثبت شد · ${clockFa(now)}');
      expect(shortTimeFa(now.subtract(const Duration(days: 1)), now), 'دیروز');
    });

    test('the red count reads in Persian digits', () {
      expect(unreadBadge(3), '۳');
      expect(unreadBadge(120), '۹۹+');
      expect(snippet('یک  دو\nسه', 5), 'یک دو…');
    });
  });

  group('C4.1 sign-in and C4.2 the list', () {
    testWidgets('signed out: the sign-in; after it, the open list with the unread dot and «باز ۲»', (tester) async {
      final h = Harness();
      await h.session.load();
      await at(tester, kWindow, h.app());
      expect(find.text(kSignInHeading), findsOneWidget);
      expect(find.text(noAccountLine('021-44280505')), findsOneWidget);
      await signIn(tester, h);
      expect(find.text(kMyRequests), findsOneWidget);
      expect(find.byKey(const ValueKey('c4-unread-$reqId')), findsOneWidget);
      expect(find.byKey(const ValueKey('c4-unread-r2')), findsNothing);
      expect(find.text('$kOpenTab ۲'), findsOneWidget);
      expect(find.textContaining('parskar.reception'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('c4-tab-closed')));
      await settle(tester);
      expect(find.byKey(const ValueKey('c4-row-closed-1')), findsOneWidget);
      expect(h.portal.sent('GET /customer/requests').last.url.queryParameters['scope'], 'closed');
      await tester.tap(find.byKey(const ValueKey('c4-back')));
      expect(h.backed, isTrue);
    });

    testWidgets('a wrong password shows the portal\'s text and keeps nothing', (tester) async {
      final h = Harness();
      h.portal.on('POST /customer/login', (_) => FakePortal.error(401, 'invalid', 'نام کاربری یا رمز درست نیست.'));
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      expect(find.text('نام کاربری یا رمز درست نیست.'), findsOneWidget);
      expect(await h.box.read(), isNull);
      expect(screenText(tester), isNot(contains('pass-word-1'))); // the password field is cleared
    });

    testWidgets('an expired token goes back to sign-in and says so; the token is deleted', (tester) async {
      final h = Harness();
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      h.portal.on('GET /customer/requests', (_) => FakePortal.error(401, 'expired', 'ورود شما تمام شده است.'));
      await tester.tap(find.byKey(const ValueKey('c4-tab-closed')));
      await settle(tester);
      expect(find.text(kSignInHeading), findsOneWidget);
      expect(find.text(kSignInExpiredText), findsOneWidget);
      expect(await h.box.read(), isNull);
    });

    testWidgets('«خروج» from «حساب» calls /logout, deletes the token, and customer B never sees A\'s rows',
        (tester) async {
      final h = Harness();
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      expect(find.byKey(const ValueKey('c4-row-$reqId')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('c4-account')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('c4-account-signout')));
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(h.portal.sent('POST /customer/logout'), hasLength(1));
      expect(await h.box.read(), isNull);
      expect(find.text(kSignInHeading), findsOneWidget);

      // Customer B of another organization: the portal's RLS gives B's rows only, and nothing of A's stays on screen.
      h.portal.on('POST /customer/login',
          (_) => {...loginJson(token: 'b-token'), 'customer': customerJson(id: 'c2', name: 'ب')});
      h.portal.on(
          'GET /customer/requests',
          (_) => {
                'rows': [rowJson(id: 'b-1', unread: false)]
              });
      await signIn(tester, h);
      expect(find.byKey(const ValueKey('c4-row-$reqId')), findsNothing);
      expect(find.byKey(const ValueKey('c4-row-b-1')), findsOneWidget);
      expect(h.portal.sent('GET /customer/requests').last.headers['Authorization'], 'Bearer b-token');
    });
  });

  group('C4.4 consent (security)', () {
    testWidgets('code mode: nothing is read or sent before the press; the press sends ID and code once',
        (tester) async {
      final logs = <String>[];
      final saved = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      try {
        final h = Harness(consentMode: 'code');
        await h.session.load();
        await at(tester, kWindow, h.app());
        await signIn(tester, h);
        await openRequest(tester);
        expect(find.text(kConnectTitle), findsOneWidget);
        expect(find.textContaining('شناسه و رمز یک‌بارمصرف'), findsOneWidget);
        expect(h.codeReads, 0, reason: 'never read automatically');
        expect(h.portal.sent('POST /customer/requests/$reqId/device'), isEmpty);

        await tester.tap(find.byKey(const ValueKey('c4-allow')));
        await settle(tester);
        expect(h.codeReads, 1);
        final sent = h.portal.sent('POST /customer/requests/$reqId/device').single;
        expect(h.portal.body(sent), {'rustdeskId': kPcId, 'code': kCode});
        expect(sent.url.toString(), isNot(contains(kCode)));
        expect(find.text('ثبت شد.'), findsOneWidget); // the portal's answer
        expect(screenText(tester), isNot(contains(kCode)), reason: 'never shown');
        expect(logs.join('\n'), isNot(contains(kCode)), reason: 'never logged');
        // Nothing else carried it: no message, no other request.
        for (final r in h.portal.requests.where((r) => r != sent)) {
          expect(r.body, isNot(contains(kCode)));
        }
      } finally {
        debugPrint = saved;
      }
    });

    testWidgets('click mode: only this PC\'s ID; the code is never read and «پذیرفتن» is still asked for',
        (tester) async {
      final h = Harness(consentMode: 'click');
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await openRequest(tester);
      expect(find.textContaining('«پذیرفتن»'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('c4-allow')));
      await settle(tester);
      expect(h.portal.body(h.portal.sent('POST /customer/requests/$reqId/device').single), {'rustdeskId': kPcId});
      expect(h.codeReads, 0);
    });

    testWidgets('a press the technician made from his side is ignored: nothing read, nothing sent', (tester) async {
      final h = Harness(consentMode: 'code')..local = false;
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await openRequest(tester);
      await tester.tap(find.byKey(const ValueKey('c4-allow')));
      await settle(tester);
      expect(h.codeReads, 0);
      expect(h.portal.sent('POST /customer/requests/$reqId/device'), isEmpty);
    });

    testWidgets('while a technician is connected the button waits', (tester) async {
      final h = Harness(consentMode: 'code');
      await h.session.load();
      await at(tester, kWindow, h.app(connectedNow: true));
      await signIn(tester, h);
      await openRequest(tester);
      expect(find.text(kAllowInSession), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('c4-allow')));
      await settle(tester);
      expect(h.codeReads, 0);
      expect(h.portal.sent('POST /customer/requests/$reqId/device'), isEmpty);
    });

    testWidgets('no code ready yet: says so and sends nothing', (tester) async {
      final h = Harness(consentMode: 'code');
      await h.session.load();
      final w = MaterialApp(
          home: Scaffold(
              body: DolphinCustomerRequests(
                  session: h.session, id: kPcId, readCode: () => '', onBack: () {}, refreshEvery: null)));
      await at(tester, kWindow, w);
      await signIn(tester, h);
      await openRequest(tester);
      await tester.tap(find.byKey(const ValueKey('c4-allow')));
      await settle(tester);
      expect(find.text(kMsgCodeNotReady), findsOneWidget);
      expect(h.portal.sent('POST /customer/requests/$reqId/device'), isEmpty);
    });

    testWidgets('a normal next step from the portal shows as information', (tester) async {
      final h = Harness(consentMode: 'click');
      h.portal.on('POST /customer/requests/$reqId/device',
          (_) => FakePortal.json({'error': 'staff_call', 'message': 'کارشناس خودش وصل می‌شود.', 'notice': true}, 409));
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await openRequest(tester);
      await tester.tap(find.byKey(const ValueKey('c4-allow')));
      await settle(tester);
      final text = find.text('کارشناس خودش وصل می‌شود.');
      expect(text, findsOneWidget);
      expect(textColorOf(tester, text), DolphinColors.azureText);
    });
  });

  group('C4.4 the rest of one request', () {
    testWidgets('chat bubbles, a message sent, the live session\'s «پایان جلسه»', (tester) async {
      final h = Harness(consentMode: 'click');
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await openRequest(tester);
      expect(find.text('ساعت ۱۱ وصل می‌شوم.'), findsOneWidget);
      expect(find.text(kFilesTitle), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('c4-message')), 'سلام');
      await tester.tap(find.byKey(const ValueKey('c4-send-message')));
      await settle(tester);
      expect(h.portal.body(h.portal.sent('POST /customer/requests/$reqId/messages').single), {'body': 'سلام'});

      h.portal.on('GET /customer/requests/$reqId', (_) => detailJson(consentMode: 'click', live: true));
      h.portal.on('POST /customer/requests/$reqId/end-session', (_) => {'ok': true});
      await tester.tap(find.byKey(const ValueKey('c4-back')));
      await settle(tester);
      await openRequest(tester);
      expect(find.byKey(const ValueKey('c4-connect-box')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('c4-end-session')));
      await settle(tester);
      expect(h.portal.sent('POST /customer/requests/$reqId/end-session'), hasLength(1));
    });

    testWidgets('a call a technician opened has no description; a closed request has no composer', (tester) async {
      final h = Harness(consentMode: 'click');
      final j = detailJson(consentMode: 'click', show: false);
      (j['request'] as Map<String, dynamic>)
        ..['description'] = null
        ..['status'] = 'resolved'
        ..['result'] = 'چاپگر دوباره نصب شد.';
      h.portal.on('GET /customer/requests/$reqId', (_) => j);
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await openRequest(tester);
      expect(find.text('از صبح فاکتورها چاپ نمی‌شوند.'), findsOneWidget); // the message, not a description
      expect(find.text('چاپگر دوباره نصب شد.'), findsOneWidget);
      expect(find.byKey(const ValueKey('c4-message')), findsNothing);
      expect(find.text(kClosedNote), findsOneWidget);
      expect(find.byKey(const ValueKey('c4-cancel-request')), findsNothing);
    });
  });

  group('C4.3 a new request', () {
    testWidgets('fields checked, this PC\'s ID sent by itself, then the request opens', (tester) async {
      final h = Harness();
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await tester.tap(find.byKey(const ValueKey('c4-new')));
      await settle(tester);
      expect(find.text(idGoesLine(kPcId)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('c4-send-request')));
      await settle(tester);
      expect(find.text(kRequestFieldsError), findsOneWidget);
      expect(h.portal.sent('POST /customer/requests'), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('c4-subject')), 'چاپگر کار نمی‌کند');
      await tester.enterText(find.byKey(const ValueKey('c4-description')), 'از صبح فاکتورها چاپ نمی‌شوند');
      await tester.tap(find.byKey(const ValueKey('c4-urgent')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('c4-send-request')));
      await settle(tester);
      final body = h.portal.body(h.portal.sent('POST /customer/requests').single);
      expect(body['rustdeskId'], kPcId);
      expect(body['priority'], 'urgent');
      expect(body.containsKey('code'), isFalse);
      expect(h.shots, 0, reason: 'the screenshot is off by default');
      expect(find.text('#۱۲۴'), findsOneWidget); // the request opened
    });

    testWidgets('«عکس صفحه را هم بفرست»: the picture is shown first; «انصراف» sends nothing', (tester) async {
      final h = Harness();
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      await tester.tap(find.byKey(const ValueKey('c4-new')));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('c4-subject')), 'چاپگر کار نمی‌کند');
      await tester.enterText(find.byKey(const ValueKey('c4-description')), 'از صبح فاکتورها چاپ نمی‌شوند');
      await tester.tap(find.byKey(const ValueKey('c4-screenshot')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('c4-send-request')));
      await settle(tester);
      expect(h.shots, 1);
      expect(find.text('عکس صفحه برای پشتیبانی'), findsOneWidget); // DD-48's confirm
      await tester.tap(find.text('انصراف').last);
      await settle(tester);
      expect(h.portal.sent('POST /customer/requests'), isEmpty);
    });
  });

  group('C4.5 the account', () {
    testWidgets('mustChangePassword: the password screen first, no way back; the change opens the list',
        (tester) async {
      final h = Harness(mustChange: true);
      h.portal.on('POST /customer/password', (_) => {'ok': true, 'message': 'رمز عوض شد.'});
      await h.session.load();
      await at(tester, kWindow, h.app());
      await signIn(tester, h);
      expect(find.text(kMustChangeLine), findsOneWidget);
      expect(find.byKey(const ValueKey('c4-back')), findsNothing);
      expect(h.portal.sent('GET /customer/requests'), isEmpty);
      expect(h.portal.sent('GET /customer/unread'), isEmpty);
      await tester.enterText(find.byKey(const ValueKey('c4-current')), 'old-pass-1');
      await tester.enterText(find.byKey(const ValueKey('c4-next')), 'new-pass-12');
      await tester.enterText(find.byKey(const ValueKey('c4-repeat')), 'new-pass-12');
      await tester.tap(find.byKey(const ValueKey('c4-save-password')));
      await settle(tester);
      expect(find.text(kMyRequests), findsOneWidget);
    });
  });

  group('C4.6 the main window row', () {
    DolphinHomeView home({int unread = 0, bool hint = true}) => DolphinHomeView(
        id: kPcId,
        state: DolphinServerState.ready,
        onCopy: () {},
        phone: '021-44280505',
        siteLabel: 'x',
        onRequests: () {},
        unread: unread,
        requestsHint: hint);

    testWidgets('the red count in Persian digits; none at 0; the who-for line only while signed out', (tester) async {
      await at(tester, const Size(380, 900), MaterialApp(home: Scaffold(body: home(unread: 3, hint: false))));
      expect(find.byKey(const ValueKey('dolphin-requests-unread')), findsOneWidget);
      expect(find.text('۳'), findsOneWidget);
      expect(find.text(kRequestsWhoFor), findsNothing);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: home())));
      expect(find.byKey(const ValueKey('dolphin-requests-unread')), findsNothing);
      expect(find.text(kRequestsWhoFor), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('the row reads at AA (${dark ? 'dark' : 'light'})', (tester) async {
        await at(tester, const Size(380, 900), MaterialApp(home: Scaffold(body: home(unread: 12))), dark: dark);
        expectAllTextReadable(tester);
      });
    }
  });

  group('sizes and contrast', () {
    /// Reaches each screen in turn and runs [check] on it.
    Future<void> everyScreen(WidgetTester tester, Size size, bool dark, void Function(String screen) check) async {
      final h = Harness(consentMode: 'code');
      await h.session.load();
      await at(tester, size, h.app(), dark: dark);
      check('sign-in');
      await signIn(tester, h);
      check('list');
      await tester.tap(find.byKey(const ValueKey('c4-new')));
      await settle(tester);
      check('new request');
      await tester.tap(find.byKey(const ValueKey('c4-back')));
      await settle(tester);
      await openRequest(tester);
      check('one request');
      await tester.tap(find.byKey(const ValueKey('c4-back')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('c4-account')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('c4-account-password')));
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(find.text(kCurrentPassword), findsOneWidget);
      check('account');
    }

    for (final size in [kWindow, kMinimum]) {
      testWidgets('nothing overflows at ${size.width.toInt()} × ${size.height.toInt()}', (tester) async {
        await everyScreen(tester, size, false, (screen) {
          expect(tester.takeException(), isNull, reason: screen);
        });
      });
    }

    for (final dark in [false, true]) {
      testWidgets('every screen reads at AA (${dark ? 'dark' : 'light'})', (tester) async {
        await everyScreen(tester, kWindow, dark, (_) => expectAllTextReadable(tester));
      });
    }
  });
}
