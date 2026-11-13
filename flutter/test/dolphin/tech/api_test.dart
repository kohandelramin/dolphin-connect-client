import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_portal.dart';

const pcId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const reqId = '22222222-2222-4222-8222-222222222222';

void main() {
  late FakePortal portal;
  late ApiClient api;
  setUp(() {
    portal = FakePortal();
    api = apiOn(portal);
  });

  group('sign-in', () {
    test('login sends username and password without a Bearer header and parses the staff', () async {
      portal.on('POST /login', (_) => {
            'token': 'new-token',
            'expiresAt': '2026-11-14T18:00:00.000Z',
            'staff': {'id': 's1', 'name': 'علی', 'role': 'technician', 'rustdeskId': null},
          });
      final r = await api.login(' admin.local ', 'pw');
      expect(r.token, 'new-token');
      expect(r.expiresAt, DateTime.utc(2026, 11, 14, 18));
      expect(r.staff.role, StaffRole.technician);
      expect(r.staff.rustdeskId, isNull);
      final req = portal.sent('POST /login').single;
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(portal.body(req), {'username': 'admin.local', 'password': 'pw'});
      expect(r.toString(), isNot(contains('new-token')));
    });

    test('a wrong password is ApiError invalid with the portal\'s Persian text, not SignInExpired', () async {
      portal.on('POST /login', (_) => FakePortal.error(401, 'invalid', 'نام کاربری یا رمز عبور درست نیست.'));
      final events = <SignInExpired>[];
      api.signInExpired.listen(events.add);
      await expectLater(
          api.login('a', 'b'),
          throwsA(isA<ApiError>()
              .having((e) => e.code, 'code', 'invalid')
              .having((e) => e.message, 'message', 'نام کاربری یا رمز عبور درست نیست.')
              .having((e) => e is SignInExpired, 'expired', false)));
      await settle();
      expect(events, isEmpty);
    });

    test('rate limited is 429 rate_limited', () async {
      portal.on('POST /login', (_) => FakePortal.error(429, 'rate_limited', 'تلاش‌های ناموفق زیاد بود.'));
      await expectLater(api.login('a', 'b'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 429)));
    });

    test('logout and rustdesk-id send the Bearer token', () async {
      portal.on('POST /logout', (_) => {'ok': true});
      portal.on('POST /me/rustdesk-id', (_) => {'ok': true});
      await api.logout();
      await api.setMyRustdeskId('987654321');
      expect(portal.sent('POST /logout').single.headers['Authorization'], 'Bearer tok-secret-123');
      expect(portal.body(portal.sent('POST /me/rustdesk-id').single), {'rustdeskId': '987654321'});
    });

    test('401 expired throws SignInExpired and fires the stream', () async {
      portal.on('GET /config', (_) => FakePortal.error(401, 'expired', 'ورود شما تمام شده است؛ دوباره وارد شوید.'));
      final events = <SignInExpired>[];
      api.signInExpired.listen(events.add);
      await expectLater(api.config(), throwsA(isA<SignInExpired>()));
      await settle();
      expect(events, hasLength(1));
      expect(events.single.message, 'ورود شما تمام شده است؛ دوباره وارد شوید.');
    });

    test('no token: SignInExpired without asking the portal', () async {
      final a = apiOn(portal, token: null);
      await expectLater(a.computers(const ComputerQuery()), throwsA(isA<SignInExpired>()));
      expect(portal.requests, isEmpty);
    });

    test('exceptions never carry the token', () async {
      portal.on('GET /config', (_) => FakePortal.error(500, 'server', 'خطای سرور'));
      try {
        await api.config();
        fail('should throw');
      } catch (e) {
        expect(e.toString(), isNot(contains('tok-secret-123')));
      }
    });
  });

  group('computers', () {
    test('query parameters follow the contract', () async {
      portal.on('GET /computers', (_) => pageJson([]));
      await api.computers(
          const ComputerQuery(q: ' acc ', view: PcView.online, tag: 'حسابداری', orgId: 'o1', sort: PcSort.name, ascending: true),
          cursor: '2');
      final p = portal.sent('GET /computers').single.url.queryParameters;
      expect(p, {'q': 'acc', 'online': '1', 'tag': 'حسابداری', 'org': 'o1', 'sort': 'name', 'dir': 'asc', 'cursor': '2'});
      portal.requests.clear();
      await api.computers(const ComputerQuery(view: PcView.favorite));
      expect(portal.sent('GET /computers').single.url.queryParameters, {'favorite': '1', 'sort': 'seen'});
    });

    test('rows, next and counts parse; display name falls back label → hostname → ID', () async {
      portal.on(
          'GET /computers',
          (_) => pageJson([
                pcJson(pcId, session: {'staffName': 'رضا', 'mine': false, 'requestId': reqId}),
                pcJson('b', label: null, hostname: 'HOST'),
                pcJson('c', label: ' ', hostname: null, rustdeskId: '555666777'),
              ], next: '2', favorite: 1));
      final page = await api.computers(const ComputerQuery());
      expect(page.next, '2');
      expect(page.counts.favorite, 1);
      final pc = page.rows.first;
      expect(pc.organization.colorValue, 0xFF1D4ED8);
      expect(pc.session!.staffName, 'رضا');
      expect(pc.session!.mine, isFalse);
      expect(pc.lastSeenAt, DateTime.utc(2026, 11, 14, 10));
      expect(pc.fromCache, isFalse);
      expect(page.rows.map((c) => c.displayName), ['پذیرش', 'HOST', '555666777']);
    });

    test('a field of the wrong type is a readable Persian error, not a crash', () async {
      portal.on('GET /computers', (_) => pageJson([pcJson(pcId)..['online'] = 'yes']));
      await expectLater(api.computers(const ComputerQuery()),
          throwsA(isA<ApiError>().having((e) => e.code, 'code', 'bad_answer').having((e) => e.message, 'm', kMsgBadAnswer)));
    });

    test('an HTML page instead of JSON is bad_answer', () async {
      portal.on('GET /computers', (_) => http.Response('<html>captive</html>', 200));
      await expectLater(api.computers(const ComputerQuery()), throwsA(isA<ApiError>().having((e) => e.code, 'c', 'bad_answer')));
    });

    test('detail: the PC, the open call, history of both kinds, sent today, tags', () async {
      portal.on(
          'GET /computers/$pcId',
          (_) => {
                'computer': {
                  ...pcJson(pcId),
                  'customerName': 'پارس',
                  'ownerName': null,
                  'consentMode': 'code',
                  'clientVersion': '2.1.0'
                },
                'call': {
                  'requestId': reqId,
                  'consentMode': 'click',
                  'sessionLive': true,
                  'connectedSince': null,
                  'hadConnection': false,
                  'reasonId': null,
                  'contactName': 'رضا',
                  'contactPhone': '09120000000',
                },
                'history': [
                  {
                    'kind': 'request',
                    'at': '2026-11-14T09:00:00.000Z',
                    'id': reqId,
                    'number': 12,
                    'subject': 'چاپگر',
                    'openedBy': 'customer',
                    'status': 'resolved',
                    'assigneeName': 'علی',
                    'resolvedAt': '2026-11-14T09:30:00.000Z',
                    'resolutionNote': null,
                    'pcName': 'PC-1',
                  },
                  {
                    'kind': 'connection',
                    'at': '2026-11-14T08:00:00.000Z',
                    'id': 7,
                    'pcName': 'PC-1',
                    'technician': 'علی',
                    'verified': true,
                    'connType': 0,
                    'closedAt': null,
                    'closeReason': null,
                    'files': 2,
                  },
                ],
                'sentToday': [
                  {'id': 'r1', 'kind': 'screenshot', 'size': 1200, 'note': null, 'createdAt': '2026-11-14T09:10:00.000Z', 'url': '/api/app/v1/reports/r1'},
                ],
                'tags': ['پذیرش'],
              });
      final d = await api.computer(pcId);
      expect(d.customerName, 'پارس');
      expect(d.consentMode, ConsentMode.code);
      expect(d.call!.sessionLive, isTrue);
      expect(d.call!.contactPhone, '09120000000');
      expect(d.history[0], isA<HistoryRequest>().having((h) => h.number, 'n', 12));
      expect(d.history[1], isA<HistoryConnection>().having((h) => h.files, 'files', 2));
      expect(d.sentToday.single.url, '/api/app/v1/reports/r1');
      expect(d.tags, ['پذیرش']);
    });

    test('detail without a call', () async {
      portal.on('GET /computers/$pcId', (_) => {'computer': pcJson(pcId), 'call': null, 'history': [], 'sentToday': [], 'tags': []});
      final d = await api.computer(pcId);
      expect(d.call, isNull);
      expect(d.consentMode, isNull);
    });

    test('favorite returns what the portal saved', () async {
      portal.on('POST /computers/$pcId/favorite', (r) => {'favorite': jsonDecode(r.body)['on']});
      expect(await api.setFavorite(pcId, true), isTrue);
      expect(portal.body(portal.requests.single), {'on': true});
    });

    test('not found surfaces the portal\'s message', () async {
      portal.on('GET /computers/$pcId', (_) => FakePortal.error(404, 'not_found', 'رایانه پیدا نشد.'));
      await expectLater(api.computer(pcId), throwsA(isA<ApiError>().having((e) => e.message, 'm', 'رایانه پیدا نشد.')));
    });
  });

  group('calls', () {
    test('startCall parses the answer; takeover only when asked', () async {
      portal.on('POST /calls', (_) => callJson);
      final c = await api.startCall(pcId);
      expect(c.requestId, reqId);
      expect(c.authorizedUntil, DateTime.utc(2026, 11, 14, 12));
      expect(c.consentMode, ConsentMode.click);
      expect(c.waiting, isFalse);
      expect(portal.body(portal.requests.last), {'deviceId': pcId});
      await api.startCall(pcId, takeover: true);
      expect(portal.body(portal.requests.last), {'deviceId': pcId, 'takeover': true});
    });

    test('in_session_other carries holderName in extra', () async {
      portal.on('POST /calls', (_) => FakePortal.error(409, 'in_session_other', 'این رایانه در جلسه با رضا است.', {'holderName': 'رضا'}));
      await expectLater(
          api.startCall(pcId),
          throwsA(isA<ApiError>()
              .having((e) => e.code, 'code', 'in_session_other')
              .having((e) => e.extra['holderName'], 'holder', 'رضا')));
    });

    test('a waiting code-mode call has no authorizedUntil', () async {
      portal.on('POST /demo', (_) => {...callJson, 'authorizedUntil': null, 'consentMode': 'code', 'waiting': true});
      final c = await api.startDemo(pcId);
      expect(c.waiting, isTrue);
      expect(c.authorizedUntil, isNull);
      expect(portal.sent('POST /demo'), hasLength(1));
    });

    test('POST is never retried, even after a network failure', () async {
      portal.on('POST /calls', (_) => throw const SocketException('Connection refused'));
      await expectLater(api.startCall(pcId), throwsA(isA<PortalUnreachable>()));
      expect(portal.sent('POST /calls'), hasLength(1));
    });

    test('end, reason, note, message bodies', () async {
      for (final r in ['end', 'reason', 'note', 'message']) {
        portal.on('POST /calls/$reqId/$r', (_) => {'ok': true});
      }
      await api.endCall(reqId, reasonId: 'rs1', note: '  حل شد  ');
      await api.endCall(reqId);
      await api.setReason(reqId, null);
      await api.addNote(reqId, 'داخلی');
      await api.sendMessage(reqId, 'سلام');
      expect(portal.requests.map(portal.body).toList(), [
        {'reasonId': 'rs1', 'note': 'حل شد'},
        <String, dynamic>{},
        {'reasonId': null},
        {'text': 'داخلی'},
        {'text': 'سلام'},
      ]);
    });

    test('end refused: the portal\'s reason', () async {
      portal.on('POST /calls/$reqId/end', (_) => FakePortal.error(409, 'closed', 'این تماس پیش‌تر بسته شده بود.'));
      await expectLater(api.endCall(reqId), throwsA(isA<ApiError>().having((e) => e.code, 'c', 'closed')));
    });
  });

  group('requests, organizations, history, snippets', () {
    Map<String, dynamic> requestJson({String openedBy = 'app'}) => {
          'id': reqId,
          'number': 5,
          'subject': 'تماس',
          'status': 'submitted',
          'priority': 'urgent',
          'openedBy': openedBy,
          'kind': 'support',
          'organization': orgA,
          'customerName': null,
          'contactName': 'رضا',
          'contactPhone': null,
          'deviceId': pcId,
          'pcName': 'PC-1',
          'rustdeskId': '123456789',
          'assigneeName': null,
          'mine': false,
          'createdAt': '2026-11-14T09:00:00.000Z',
          'resolvedAt': null,
        };

    test('requests by scope with counts', () async {
      portal.on('GET /requests', (_) => {'rows': [requestJson()], 'next': null, 'counts': {'queue': 3, 'mine': 1}});
      final p = await api.requests(RequestScope.closed, cursor: '2');
      expect(portal.requests.single.url.queryParameters, {'scope': 'closed', 'cursor': '2'});
      expect(p.queueCount, 3);
      expect(p.mineCount, 1);
      expect(p.rows.single.isCallback, isTrue);
      expect(p.rows.single.urgent, isTrue);
    });

    test('take: 409 taken', () async {
      portal.on('POST /requests/$reqId/take', (_) => FakePortal.error(409, 'taken', 'این درخواست دیگر در صف نیست.'));
      await expectLater(api.takeRequest(reqId), throwsA(isA<ApiError>().having((e) => e.code, 'c', 'taken')));
    });

    test('organizations list and detail (fixedPassword is a flag)', () async {
      final row = {...orgA, 'dealerCode': 'D1', 'consentMode': 'click', 'active': true, 'city': 'تهران', 'phones': '021', 'training': false};
      portal.on('GET /organizations', (_) => {'rows': [row], 'next': '2'});
      portal.on('GET /organizations/${orgA['id']}', (_) => {
            'organization': {...row, 'fixedPassword': true, 'contactName': 'رضا', 'contractNote': null},
            'customers': [
              {'id': 'c1', 'name': 'مینا', 'phone': null, 'active': true}
            ],
          });
      final list = await api.organizations(q: 'گردش');
      expect(portal.requests.first.url.queryParameters, {'q': 'گردش'});
      expect(list.next, '2');
      expect(list.rows.single.colorValue, 0xFF1D4ED8);
      final d = await api.organization(orgA['id']!);
      expect(d.fixedPassword, isTrue);
      expect(d.customers.single.name, 'مینا');
    });

    test('history by device or organization', () async {
      portal.on('GET /history', (_) => {'rows': []});
      await api.history(deviceId: pcId);
      await api.history(organizationId: 'o1');
      expect(portal.requests[0].url.queryParameters, {'deviceId': pcId});
      expect(portal.requests[1].url.queryParameters, {'organizationId': 'o1'});
    });

    test('snippets and snippet used (never the text)', () async {
      portal.on('GET /snippets', (_) => {'rows': [{'id': 'n1', 'title': 'سلام', 'body': 'متن'}]});
      portal.on('POST /snippets/n1/used', (_) => {'ok': true});
      expect((await api.snippets()).single.body, 'متن');
      await api.snippetUsed('n1', rustdeskId: '123456789');
      expect(portal.body(portal.requests.last), {'rustdeskId': '123456789'});
    });
  });

  group('notifications and config', () {
    test('notifications: since in ISO UTC, unknown kinds dropped', () async {
      portal.on('GET /notifications', (_) => [
            {'id': 'callback:r1', 'kind': 'callback', 'title': 't', 'body': 'b', 'deviceId': pcId, 'requestId': 'r1', 'at': '2026-11-14T10:00:00.000Z'},
            {'id': 'x:1', 'kind': 'future_kind', 'title': 't', 'body': 'b', 'at': '2026-11-14T10:01:00.000Z'},
            {'id': 'auth:a:1', 'kind': 'auth_expiring', 'title': 't', 'body': 'b', 'deviceId': pcId, 'at': '2026-11-14T10:02:00.000Z'},
          ]);
      final list = await api.notifications(since: DateTime.utc(2026, 11, 14, 9, 30));
      expect(portal.requests.single.url.queryParameters['since'], '2026-11-14T09:30:00.000Z');
      expect(list.map((n) => n.kind), [NotificationKind.callback, NotificationKind.authExpiring]);
      expect(list.first.requestId, 'r1');
    });

    test('config: switches parsed, theme passed through untouched, latest and reasons', () async {
      final theme = {
        'v': 1,
        'light': {'azure': '#1462e0', 'radius': 8}
      };
      portal.on('GET /config', (_) => {
            'switches': {'direct-route': 'hidden', 'new-key': 'forced', 'safe-mode': 'bogus'},
            'theme': theme,
            'latest': {
              'version': '2.1.0',
              'technician': {'url': '/api/app/v1/download/technician', 'sha256': 'ab' * 32, 'size': 1234}
            },
            'callReasons': [
              {'id': 'rs1', 'name': 'چاپگر'}
            ],
          });
      final c = await api.config();
      expect(c.switches.mode(DolphinSwitch.directRoute), SwitchMode.hidden);
      expect(c.switches.mode('new-key'), SwitchMode.forced);
      expect(c.switches.mode(DolphinSwitch.safeMode), SwitchMode.hidden); // bad mode → the default
      expect(c.theme, theme);
      expect(jsonDecode(c.themeJson!), theme);
      expect(c.latest!.version, '2.1.0');
      expect(c.latest!.size, 1234);
      expect(c.callReasons.single.name, 'چاپگر');
    });

    test('config with no theme and no latest', () async {
      portal.on('GET /config', (_) => {'switches': {}, 'theme': null, 'latest': null, 'callReasons': []});
      final c = await api.config();
      expect(c.theme, isNull);
      expect(c.themeJson, isNull);
      expect(c.latest, isNull);
    });
  });

  group('network failures (TD-1)', () {
    test('a GET is tried once more after a network failure', () async {
      portal.onSeq('GET /snippets', [
        (_) => throw const SocketException('Connection reset'),
        (_) => {'rows': []},
      ]);
      expect(await api.snippets(), isEmpty);
      expect(portal.sent('GET /snippets'), hasLength(2));
    });

    test('a GET is tried once more after 503, then says portal down', () async {
      portal.on('GET /snippets', (_) => http.Response('busy', 503));
      await expectLater(api.snippets(),
          throwsA(isA<PortalUnreachable>().having((e) => e.reason, 'r', OfflineReason.portalDown).having((e) => e.message, 'm', kMsgPortalDown)));
      expect(portal.sent('GET /snippets'), hasLength(2));
    });

    test('a failed name lookup is "no internet"', () async {
      portal.on('GET /snippets', (_) => throw const SocketException("Failed host lookup: 'portal.test'"));
      await expectLater(api.snippets(), throwsA(isA<PortalUnreachable>().having((e) => e.reason, 'r', OfflineReason.noInternet)));
    });

    test('no network interface is "no internet"', () async {
      final a = apiOn(portal, probe: FixedProbe(false));
      portal.on('GET /snippets', (_) => throw const SocketException('Connection refused'));
      await expectLater(a.snippets(), throwsA(isA<PortalUnreachable>().having((e) => e.reason, 'r', OfflineReason.noInternet)));
    });

    test('no answer within the read timeout is "slow"', () async {
      final a = apiOn(portal, readTimeout: const Duration(milliseconds: 30));
      portal.on('GET /snippets', (_) => Completer<Object?>().future);
      await expectLater(a.snippets(), throwsA(isA<PortalUnreachable>().having((e) => e.reason, 'r', OfflineReason.slow)));
      expect(portal.sent('GET /snippets'), hasLength(2));
    });

    test('a 500 without a body still has Persian text', () async {
      portal.on('GET /snippets', (_) => http.Response('', 500));
      await expectLater(api.snippets(), throwsA(isA<ApiError>().having((e) => e.message, 'm', kMsgServer)));
    });

    test('isDnsFailure knows the Windows codes', () {
      expect(isDnsFailure(const SocketException('x', osError: OSError('No such host', 11001))), isTrue);
      expect(isDnsFailure(const SocketException('x', osError: OSError('refused', 10061))), isFalse);
    });
  });

  group('downloads', () {
    test('only App API paths get the token', () {
      expect(api.downloadUri('/api/app/v1/reports/r1').toString(), 'http://portal.test/api/app/v1/reports/r1');
      for (final bad in ['https://evil.example/x', '/download/x', '/api/app/v1/../x', '//evil.example/api/app/v1/x']) {
        expect(() => api.downloadUri(bad), throwsA(isA<ApiError>()), reason: bad);
      }
    });

    test('download writes the file and checks the size', () async {
      final dir = await Directory.systemTemp.createTemp('dc-tech-dl');
      addTearDown(() => dir.delete(recursive: true));
      portal.on('GET /reports/r1', (_) => http.Response.bytes(List.filled(10, 7), 200));
      final f = File('${dir.path}/r1.png');
      expect(await api.download('/api/app/v1/reports/r1', f, expectedSize: 10), 10);
      expect(await f.length(), 10);
      expect(portal.requests.last.headers['Authorization'], 'Bearer tok-secret-123');
      final g = File('${dir.path}/r2.png');
      await expectLater(api.download('/api/app/v1/reports/r1', g, expectedSize: 11), throwsA(isA<ApiError>()));
      expect(await g.exists(), isFalse);
    });

    test('download 404 surfaces the message', () async {
      final dir = await Directory.systemTemp.createTemp('dc-tech-dl');
      addTearDown(() => dir.delete(recursive: true));
      portal.on('GET /download/technician', (_) => FakePortal.error(404, 'not_found', 'فایل برنامه‌ی کارشناس هنوز روی سرور نیست.'));
      await expectLater(api.download('/api/app/v1/download/technician', File('${dir.path}/t.exe')),
          throwsA(isA<ApiError>().having((e) => e.message, 'm', 'فایل برنامه‌ی کارشناس هنوز روی سرور نیست.')));
    });
  });

  test('parseHexColor', () {
    expect(parseHexColor('#0f766e'), 0xFF0F766E);
    expect(parseHexColor('red'), 0xFF1462E0);
    expect(parseHexColor(null), 0xFF1462E0);
  });
}
