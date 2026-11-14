import 'dart:async';
import 'dart:io';

import 'package:flutter_hbb/dolphin/customer_api/api.dart';
import 'package:flutter_hbb/dolphin/customer_api/session.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'tech/fake_portal.dart' show FakePortal, FixedProbe, settle;

// Plan 19 C4: the customer App API client, the sign-in store and the unread count, on a scripted portal.

const reqId = '33333333-3333-4333-8333-333333333333';
const fileId = '44444444-4444-4444-8444-444444444444';

Map<String, dynamic> customerJson({String id = 'c1', String name = 'پذیرش پارس‌کار'}) => {
      'id': id,
      'name': name,
      'username': 'parskar.reception',
      'organization': {'id': 'o1', 'name': 'پارس‌کار'},
    };

Map<String, dynamic> loginJson({bool mustChange = false, String token = 'cust-token-xyz'}) => {
      'token': token,
      'expiresAt': '2099-01-01T00:00:00.000Z',
      'mustChangePassword': mustChange,
      'customer': customerJson(),
    };

Map<String, dynamic> rowJson({String id = reqId, String status = 'claimed', bool unread = true, Object? product = 'حسابداری'}) => {
      'id': id,
      'number': 124,
      'subject': 'چاپگر حسابداری کار نمی‌کند',
      'product': product,
      'status': status,
      'priority': 'normal',
      'updatedAt': '2026-11-14T07:12:00.000Z',
      'lastMessage': {'authorKind': 'staff', 'authorName': 'علی رضایی', 'body': 'ساعت ۱۱ وصل می‌شوم…', 'at': '2026-11-14T07:12:00.000Z'},
      'unread': unread,
    };

Map<String, dynamic> detailJson({String consentMode = 'code', bool show = true, bool live = false, Object? attachments = const []}) => {
      'request': {...rowJson(), 'description': 'از صبح فاکتورها چاپ نمی‌شوند.', 'result': null},
      'connect': {
        'show': show,
        'technicianName': 'علی رضایی',
        'consentMode': consentMode,
        'codeState': consentMode == 'code' ? 'waiting' : 'not_needed',
        'codeSubmitted': false,
        'codeExpiresAt': null,
        'sessionLive': live,
        'deviceRustdeskId': null,
      },
      'messages': [
        {'id': 'm1', 'authorKind': 'customer', 'authorName': 'پذیرش', 'body': 'از صبح فاکتورها چاپ نمی‌شوند.', 'at': '2026-11-14T06:28:00.000Z'},
        {'id': 'm2', 'authorKind': 'staff', 'authorName': 'علی رضایی', 'body': 'ساعت ۱۱ وصل می‌شوم.', 'at': '2026-11-14T07:12:00.000Z'},
      ],
      'attachments': attachments,
    };

CustomerApi apiOn(FakePortal portal, {String? token = 'cust-token-xyz'}) => CustomerApi(
    portalUrl: 'http://portal.test', client: portal.client, token: () => token, probe: FixedProbe());

void main() {
  late FakePortal portal;
  late CustomerApi api;
  setUp(() {
    portal = FakePortal();
    api = apiOn(portal);
  });

  group('the client', () {
    test('login sends no Bearer header and parses the customer; its text never carries the token', () async {
      portal.on('POST /customer/login', (_) => loginJson(mustChange: true));
      final r = await api.login(' parskar.reception ', 'pw-123');
      expect(r.mustChangePassword, isTrue);
      expect(r.customer.organizationName, 'پارس‌کار');
      final req = portal.sent('POST /customer/login').single;
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(portal.body(req), {'username': 'parskar.reception', 'password': 'pw-123'});
      expect(r.toString(), isNot(contains('cust-token-xyz')));
    });

    test('a wrong password is the portal\'s Persian text, not an expiry', () async {
      portal.on('POST /customer/login', (_) => FakePortal.error(401, 'invalid', 'نام کاربری یا رمز درست نیست.'));
      final events = <SignInExpired>[];
      api.signInExpired.listen(events.add);
      await expectLater(api.login('a', 'b'),
          throwsA(isA<ApiError>().having((e) => e.message, 'message', 'نام کاربری یا رمز درست نیست.')));
      await settle();
      expect(events, isEmpty);
    });

    test('the list, unread, products (a bare list) and a request parse; the scope is in the query', () async {
      portal.on('GET /customer/requests', (_) => {'rows': [rowJson(), rowJson(id: 'x', status: 'submitted', unread: false, product: {'id': 'p', 'name': 'فروشگاهی'})]});
      portal.on('GET /customer/unread', (_) => {'count': 2});
      portal.on('GET /customer/products', (_) => [{'id': 'p1', 'name': 'حسابداری'}]);
      portal.on('GET /customer/requests/$reqId', (_) => detailJson());
      final rows = await api.requests(CustomerScope.closed);
      expect(portal.sent('GET /customer/requests').single.url.queryParameters, {'scope': 'closed'});
      expect(rows.first.unread, isTrue);
      expect(rows.first.lastMessage!.fromStaff, isTrue);
      expect(rows[1].product, 'فروشگاهی');
      expect(rows.first.open, isTrue);
      expect(await api.unread(), 2);
      expect((await api.products()).single.name, 'حسابداری');
      final d = await api.request(reqId);
      expect(d.connect.codeMode, isTrue);
      expect(d.connect.codeState, CodeState.waiting);
      expect(d.messages.map((m) => m.fromStaff), [false, true]);
      expect(d.files, isEmpty);
      for (final r in portal.requests) {
        expect(r.headers['Authorization'], 'Bearer cust-token-xyz');
      }
    });

    test('attachments null means the server keeps no files', () async {
      portal.on('GET /customer/requests/$reqId', (_) => detailJson(attachments: null));
      expect((await api.request(reqId)).files, isNull);
    });

    test('a new request carries this PC\'s ID; an unknown product is the web\'s empty choice', () async {
      portal.on('POST /customer/requests', (_) => {'id': reqId, 'number': 125});
      final c = await api.createRequest(subject: ' چاپگر ', description: 'فاکتورها چاپ نمی‌شوند', rustdeskId: '123456789');
      expect(c.number, 125);
      expect(portal.body(portal.sent('POST /customer/requests').single),
          {'productId': '', 'subject': 'چاپگر', 'description': 'فاکتورها چاپ نمی‌شوند', 'rustdeskId': '123456789'});
    });

    test('allowConnect: the ID alone in click mode, the code only when given', () async {
      portal.on('POST /customer/requests/$reqId/device', (_) => {'ok': true});
      await api.allowConnect(reqId, rustdeskId: '123456789');
      await api.allowConnect(reqId, rustdeskId: '123456789', code: 'Ab3dE6gh');
      final sent = portal.sent('POST /customer/requests/$reqId/device');
      expect(portal.body(sent[0]), {'rustdeskId': '123456789'});
      expect(portal.body(sent[1]), {'rustdeskId': '123456789', 'code': 'Ab3dE6gh'});
      expect(sent[1].url.toString(), isNot(contains('Ab3dE6gh')));
    });

    test('an error after sending the code never carries it in its text', () async {
      portal.on('POST /customer/requests/$reqId/device', (req) => FakePortal.error(400, 'invalid_code', 'رمز درست نیست.'));
      try {
        await api.allowConnect(reqId, rustdeskId: '123456789', code: 'Ab3dE6gh');
        fail('should throw');
      } on ApiError catch (e) {
        expect('$e ${e.message} ${e.extra}', isNot(contains('Ab3dE6gh')));
      }
    });

    test('403 password_change fires its stream', () async {
      portal.on('GET /customer/unread', (_) => FakePortal.error(403, 'password_change', 'اول رمز را عوض کنید.'));
      var fired = 0;
      api.passwordChangeNeeded.listen((_) => fired++);
      await expectLater(api.unread(), throwsA(isA<ApiError>()));
      await settle();
      expect(fired, 1);
    });

    test('upload: start with the upload header, chunks at the server\'s offsets, resumes after a 409 and a drop', () async {
      final size = kAttachmentChunkBytes + 10;
      portal.on('POST /api/requests/$reqId/attachments', (_) => {'id': fileId, 'received': 0});
      var puts = 0;
      portal.on('PUT /api/attachments/$fileId', (req) {
        puts++;
        final offset = int.parse(req.url.queryParameters['offset']!);
        if (puts == 1) return FakePortal.json({'error': 'offset', 'received': 5}, 409);
        if (puts == 2) throw const SocketException('reset');
        return {'received': offset + req.bodyBytes.length, 'complete': offset + req.bodyBytes.length == size};
      });
      final progress = <int>[];
      final waits = <Duration>[];
      await api.upload(reqId,
          name: 'invoice.png',
          size: size,
          read: (o, n) async => List.filled(n, 1),
          onProgress: progress.add,
          wait: (d) async => waits.add(d));
      final start = portal.sent('POST /api/requests/$reqId/attachments').single;
      expect(start.headers[kUploadHeader], '1');
      expect(portal.body(start), {'name': 'invoice.png', 'size': size});
      final offsets = portal.sent('PUT /api/attachments/$fileId').map((r) => r.url.queryParameters['offset']).toList();
      expect(offsets, ['0', '5', '5', '${kAttachmentChunkBytes + 5}']);
      expect(progress.last, size);
      expect(waits, hasLength(1));
    });

    test('upload refusals use the web\'s texts; too big and empty never reach the portal', () async {
      portal.on('POST /api/requests/$reqId/attachments', (_) => FakePortal.json({'error': 'closed'}, 400));
      await expectLater(api.upload(reqId, name: 'a', size: 3, read: (_, n) async => List.filled(n, 0)),
          throwsA(isA<ApiError>().having((e) => e.message, 'message', kMsgFileClosed)));
      await expectLater(api.upload(reqId, name: 'a', size: kAttachmentMaxBytes + 1, read: (_, n) async => const []),
          throwsA(isA<ApiError>().having((e) => e.message, 'message', kMsgFileTooBig)));
      await expectLater(api.upload(reqId, name: 'a', size: 0, read: (_, n) async => const []),
          throwsA(isA<ApiError>().having((e) => e.message, 'message', kMsgFileEmpty)));
      expect(portal.sent('POST /api/requests/$reqId/attachments'), hasLength(1));
    });

    test('a 401 signed_out from the attachment routes ends the sign-in', () async {
      portal.on('POST /api/requests/$reqId/attachments', (_) => FakePortal.json({'error': 'signed_out'}, 401));
      await expectLater(api.upload(reqId, name: 'a', size: 3, read: (_, n) async => List.filled(n, 0)),
          throwsA(isA<SignInExpired>()));
    });

    test('download streams the file with the token and checks its size', () async {
      final dir = await Directory.systemTemp.createTemp('dc-c4');
      addTearDown(() => dir.delete(recursive: true));
      portal.on('GET /api/attachments/$fileId', (_) => http.Response.bytes([1, 2, 3], 200));
      final target = File('${dir.path}/a.png');
      expect(await api.downloadFile(fileId, target, size: 3), 3);
      expect(portal.sent('GET /api/attachments/$fileId').single.headers['Authorization'], 'Bearer cust-token-xyz');
      await expectLater(api.downloadFile(fileId, File('${dir.path}/b.png'), size: 4), throwsA(isA<ApiError>()));
      expect(File('${dir.path}/b.png').existsSync(), isFalse);
    });
  });

  group('the sign-in store', () {
    late MemoryBox box;
    late CustomerSession session;
    setUp(() {
      box = MemoryBox();
      api = CustomerApi(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe());
      session = CustomerSession(api, box);
    });

    test('sign-in keeps the token in the box and hands it to the client; the password is never kept', () async {
      portal.on('POST /customer/login', (_) => loginJson());
      portal.on('GET /customer/unread', (_) => {'count': 1});
      expect(await session.signIn('parskar.reception', 'secret-pass-1'), isTrue);
      expect(session.ready, isTrue);
      final stored = (await box.read())!;
      expect(stored, contains('cust-token-xyz'));
      expect(stored, isNot(contains('secret-pass-1')));
      await api.unread();
      expect(portal.sent('GET /customer/unread').single.headers['Authorization'], 'Bearer cust-token-xyz');
    });

    test('empty fields and a wrong password say why in Persian', () async {
      expect(await session.signIn('', ''), isFalse);
      expect(session.error, kMsgFillSignIn);
      portal.on('POST /customer/login', (_) => FakePortal.error(401, 'invalid', 'نام کاربری یا رمز درست نیست.'));
      expect(await session.signIn('a', 'b'), isFalse);
      expect(session.error, 'نام کاربری یا رمز درست نیست.');
      expect(await box.read(), isNull);
    });

    test('sign-out calls /logout and deletes the token, even offline', () async {
      portal.on('POST /customer/login', (_) => loginJson());
      await session.signIn('a', 'b');
      portal.on('POST /customer/logout', (_) => throw const SocketException('down'));
      await session.signOut();
      expect(portal.sent('POST /customer/logout'), hasLength(1));
      expect(await box.read(), isNull);
      expect(session.state, CustomerSignIn.signedOut);
      expect(session.customer, isNull);
    });

    test('a 401 expired deletes the token and goes back to sign-in', () async {
      portal.on('POST /customer/login', (_) => loginJson());
      await session.signIn('a', 'b');
      portal.on('GET /customer/requests', (_) => FakePortal.error(401, 'expired', 'ورود شما تمام شده است.'));
      await expectLater(api.requests(CustomerScope.open), throwsA(isA<SignInExpired>()));
      await settle();
      await settle();
      expect(session.state, CustomerSignIn.expired);
      expect(await box.read(), isNull);
    });

    test('a stored sign-in past its expiry is dropped as expired; a good one is used and refreshed', () async {
      await box.write(StoredCustomer('old', DateTime.utc(2000), false, CustomerInfo.fromJson(customerJson())).toJson());
      await session.load();
      expect(session.state, CustomerSignIn.expired);
      expect(await box.read(), isNull);

      await box.write(StoredCustomer('tok', DateTime.utc(2099), false, CustomerInfo.fromJson(customerJson())).toJson());
      portal.on('GET /customer/me', (_) => {'customer': customerJson(name: 'نام تازه'), 'mustChangePassword': true});
      final s2 = CustomerSession(api, box);
      await s2.load();
      expect(s2.signedIn, isTrue);
      await settle();
      await settle();
      expect(s2.customer!.name, 'نام تازه');
      expect(s2.mustChangePassword, isTrue);
      expect(s2.ready, isFalse);
    });

    test('mustChangePassword: the change clears it; mismatched or same passwords never reach the portal', () async {
      portal.on('POST /customer/login', (_) => loginJson(mustChange: true));
      await session.signIn('a', 'b');
      expect(session.ready, isFalse);
      expect(await session.changePassword('old-pass-1', 'new-pass-12', 'other'), kMsgPasswordMismatch);
      expect(await session.changePassword('old-pass-1', 'old-pass-1', 'old-pass-1'), kMsgPasswordSame);
      expect(portal.sent('POST /customer/password'), isEmpty);
      portal.on('POST /customer/password', (_) => {'ok': true});
      expect(await session.changePassword('old-pass-1', 'new-pass-12', 'new-pass-12'), isNull);
      expect(portal.body(portal.sent('POST /customer/password').single), {'current': 'old-pass-1', 'next': 'new-pass-12'});
      expect(session.ready, isTrue);
      expect(await box.read(), contains('"mustChangePassword":false'));
    });

    test('a 403 password_change sends the customer to the password screen', () async {
      portal.on('POST /customer/login', (_) => loginJson());
      await session.signIn('a', 'b');
      portal.on('GET /customer/unread', (_) => FakePortal.error(403, 'password_change', 'رمز را عوض کنید.'));
      await expectLater(api.unread(), throwsA(isA<ApiError>()));
      await settle();
      await settle();
      expect(session.mustChangePassword, isTrue);
    });
  });

  group('the unread count (C4.6)', () {
    test('asked on every tick only while signed in; sign-out stops it and clears the count', () async {
      final portal = FakePortal();
      final api = CustomerApi(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe());
      final session = CustomerSession(api, MemoryBox());
      portal.on('POST /customer/login', (_) => loginJson());
      portal.on('POST /customer/logout', (_) => {'ok': true});
      portal.on('GET /customer/unread', (_) => {'count': 3});
      // 30 s in the app; a short tick here so the test runs in real time.
      const tick = Duration(milliseconds: 60);
      final poller = UnreadPoller(session, every: tick);
      addTearDown(poller.dispose);
      expect(kUnreadEvery, const Duration(seconds: 30));
      expect(poller.running, isFalse);
      await Future<void>.delayed(tick * 3);
      expect(portal.sent('GET /customer/unread'), isEmpty);

      await session.signIn('a', 'b');
      expect(poller.running, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(poller.count.value, 3);
      expect(portal.sent('GET /customer/unread'), hasLength(1)); // at once
      await Future<void>.delayed(tick * 2);
      expect(portal.sent('GET /customer/unread').length, greaterThanOrEqualTo(2));

      await session.signOut();
      expect(poller.running, isFalse);
      expect(poller.count.value, 0);
      final asked = portal.sent('GET /customer/unread').length;
      await Future<void>.delayed(tick * 3);
      expect(portal.sent('GET /customer/unread'), hasLength(asked));
    });

    testWidgets('never asked while the password must change', (tester) async {
      final portal = FakePortal();
      final api = CustomerApi(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe());
      final session = CustomerSession(api, MemoryBox());
      portal.on('POST /customer/login', (_) => loginJson(mustChange: true));
      final poller = UnreadPoller(session);
      addTearDown(poller.dispose);
      await tester.runAsync(() => session.signIn('a', 'b'));
      await tester.pump(const Duration(seconds: 61));
      expect(poller.running, isFalse);
      expect(portal.sent('GET /customer/unread'), isEmpty);
    });
  });

  test('the customer box is its own folder and DPAPI entropy, apart from the technician\'s', () {
    expect(kCustomerBoxFolder, isNot('tech'));
    expect(String.fromCharCodes(kCustomerBoxEntropy), 'dc-cust-v1');
  });
}
