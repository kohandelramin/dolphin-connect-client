import 'dart:io';

import 'package:flutter_hbb/dolphin/tech/actions.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/cache.dart';
import 'package:flutter_hbb/dolphin/tech/notifications.dart';
import 'package:flutter_hbb/dolphin/tech/repository.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_hbb/dolphin/tech/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_portal.dart';

const pcId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const reqId = '22222222-2222-4222-8222-222222222222';

class FakeLauncher implements SessionLauncher {
  final opened = <String>[];
  @override
  Future<void> open(String rustdeskId, {String? password}) async => opened.add(rustdeskId);
  @override
  Future<String> myId() async => '987654321';
  @override
  Future<List<String>> recentIds({int limit = 5}) async => ['123456789'];
}

Map<String, dynamic> detailJson({bool withCall = true, bool favorite = false}) => {
      'computer': {...pcJson(pcId, favorite: favorite), 'customerName': null, 'ownerName': null, 'consentMode': 'click', 'clientVersion': null},
      'call': withCall
          ? {
              'requestId': reqId,
              'consentMode': 'click',
              'sessionLive': false,
              'connectedSince': null,
              'hadConnection': false,
              'reasonId': null,
              'contactName': null,
              'contactPhone': null
            }
          : null,
      'history': [],
      'sentToday': [],
      'tags': [],
    };

void main() {
  late FakePortal portal;
  late ApiClient api;
  late OfflineCache cache;
  late TechRepository repo;
  late ConnectionController connection;
  late MemoryPrefs prefs;
  late FakeLauncher launcher;
  late TechActions actions;

  setUp(() {
    portal = FakePortal();
    api = apiOn(portal);
    cache = OfflineCache(MemoryBox(), now: () => DateTime.utc(2026, 11, 14, 7, 12));
    repo = TechRepository(api, cache);
    connection = ConnectionController(now: () => DateTime.utc(2026, 11, 14, 8));
    prefs = MemoryPrefs();
    launcher = FakeLauncher();
    actions = TechActions(api, launcher);
  });

  group('ConnectionController (TD-1)', () {
    test('reachable → offline with reason and since → reachable', () async {
      expect(connection.offline, isFalse);
      expect(connection.value.message, isNull);
      await expectLater(connection.track(() async => throw const PortalUnreachable(OfflineReason.noInternet)),
          throwsA(isA<PortalUnreachable>()));
      expect(connection.offline, isTrue);
      expect(connection.value.reason, OfflineReason.noInternet);
      expect(connection.value.message, kMsgNoInternet);
      expect(connection.value.since, DateTime.utc(2026, 11, 14, 8));
      connection.unreachable(const PortalUnreachable(OfflineReason.portalDown));
      expect(connection.value.reason, OfflineReason.portalDown);
      expect(connection.value.since, DateTime.utc(2026, 11, 14, 8)); // still away since the first failure
      await expectLater(connection.track(() async => throw const ApiError(404, 'not_found', 'x')), throwsA(isA<ApiError>()));
      expect(connection.offline, isFalse); // any HTTP answer means the portal is there
    });
  });

  group('DashboardController', () {
    late DashboardController dash;
    setUp(() => dash = DashboardController(repo, connection, prefs,
        actions: actions, debounce: const Duration(milliseconds: 20), retryEvery: const Duration(milliseconds: 40)));
    tearDown(() => dash.dispose());

    test('load: items, counts, paging', () async {
      portal.on('GET /computers', (r) => r.url.queryParameters['cursor'] == '2'
          ? pageJson([pcJson('b', rustdeskId: '222333444')], online: 2)
          : pageJson([pcJson('a')], next: '2', online: 2));
      var notified = 0;
      dash.addListener(() => notified++);
      await dash.load();
      expect(dash.items.map((c) => c.id), ['a']);
      expect(dash.counts.online, 2);
      expect(dash.hasMore, isTrue);
      expect(dash.loading, isFalse);
      await dash.loadMore();
      expect(dash.items.map((c) => c.id), ['a', 'b']);
      expect(dash.hasMore, isFalse);
      expect(notified, greaterThan(2));
      expect(dash.tags, ['حسابداری']);
    });

    test('portal away: the cached list, read-only, with lastUpdated; back online by itself', () async {
      portal.on('GET /computers', (_) => pageJson([pcJson('a', favorite: true)]));
      await dash.load(); // fills the cache
      portal.on('GET /computers', (_) => throw const SocketException('refused'));
      await dash.load();
      expect(dash.offline, isTrue);
      expect(connection.offline, isTrue);
      expect(dash.items.single.fromCache, isTrue);
      expect(dash.lastUpdated!.toUtc(), DateTime.utc(2026, 11, 14, 7, 12));
      expect(dash.counts.favorite, 1);
      expect(dash.hasMore, isFalse);
      expect(dash.error, isNull);
      expect(await dash.toggleFavorite(dash.items.single), isFalse); // read-only
      expect(dash.error, isNotNull);

      portal.on('GET /computers', (_) => pageJson([pcJson('a'), pcJson('b', rustdeskId: '222333444')]));
      await Future<void>.delayed(const Duration(milliseconds: 120)); // the 15 s retry, shortened
      expect(dash.offline, isFalse);
      expect(connection.offline, isFalse);
      expect(dash.items.map((c) => c.id), ['a', 'b']);
      expect(dash.lastUpdated, isNull);
    });

    test('portal away and no cache: the reason as the error', () async {
      portal.on('GET /computers', (_) => throw const SocketException("Failed host lookup: 'portal.test'"));
      await dash.load();
      expect(dash.offline, isTrue);
      expect(dash.items, isEmpty);
      expect(dash.error, kMsgNoInternet);
    });

    test('offline search filters the cache locally', () async {
      portal.on('GET /computers', (_) => pageJson([pcJson('a', label: 'پذیرش'), pcJson('b', label: 'انبار', rustdeskId: '222333444')]));
      await dash.load();
      portal.on('GET /computers', (_) => throw const SocketException('refused'));
      dash.setView(PcView.all);
      dash.search('انبار');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(dash.items.map((c) => c.id), ['b']);
    });

    test('search is debounced: one request after typing stops', () async {
      portal.on('GET /computers', (_) => pageJson([]));
      dash.search('a');
      dash.search('ac');
      dash.search('acc');
      expect(dash.query.q, 'acc');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(portal.sent('GET /computers'), hasLength(1));
      expect(portal.requests.single.url.queryParameters['q'], 'acc');
    });

    test('filters ask again at once; the same filter twice asks once', () async {
      portal.on('GET /computers', (_) => pageJson([]));
      dash.setView(PcView.online);
      dash.setView(PcView.online);
      dash.setTag('حسابداری');
      dash.setOrganization('o1');
      dash.setSort(PcSort.name, ascending: true);
      await settle();
      await settle();
      final p = portal.requests.map((r) => r.url.queryParameters).toList();
      expect(p, hasLength(4));
      expect(p.last, {'online': '1', 'tag': 'حسابداری', 'org': 'o1', 'sort': 'name', 'dir': 'asc'});
    });

    test('a slow older answer never overwrites a newer one', () async {
      var n = 0;
      portal.on('GET /computers', (_) async {
        final mine = ++n;
        if (mine == 1) await Future<void>.delayed(const Duration(milliseconds: 40));
        return pageJson([pcJson(mine == 1 ? 'old' : 'new')]);
      });
      final first = dash.load();
      dash.setView(PcView.online);
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(dash.items.map((c) => c.id), ['new']);
    });

    test('view mode tiles/list is kept in prefs', () async {
      expect(dash.viewMode, PcViewMode.tiles);
      await dash.setViewMode(PcViewMode.list);
      expect(prefs.values[kTechViewModeOption], 'list');
      final again = DashboardController(repo, connection, prefs);
      expect(again.viewMode, PcViewMode.list);
      again.dispose();
    });

    test('favourite: shown at once, put back when the portal refuses', () async {
      portal.on('GET /computers', (_) => pageJson([pcJson(pcId)]));
      await dash.load();
      portal.on('POST /computers/$pcId/favorite', (_) => {'favorite': true});
      expect(await dash.toggleFavorite(dash.items.single), isTrue);
      expect(dash.items.single.favorite, isTrue);
      expect(dash.counts.favorite, 1);
      portal.on('POST /computers/$pcId/favorite', (_) => FakePortal.error(404, 'not_found', 'رایانه پیدا نشد.'));
      expect(await dash.toggleFavorite(dash.items.single), isFalse);
      expect(dash.items.single.favorite, isTrue);
      expect(dash.error, 'رایانه پیدا نشد.');
    });

    test('recent strip joins the app\'s history with the list', () async {
      portal.on('GET /computers', (_) => pageJson([pcJson(pcId)]));
      await dash.load();
      await dash.loadRecent();
      expect(dash.recent.single.displayName, 'پذیرش');
    });

    test('reset empties everything', () async {
      portal.on('GET /computers', (_) => pageJson([pcJson(pcId)]));
      dash.search('x');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      dash.reset();
      expect(dash.items, isEmpty);
      expect(dash.query, const ComputerQuery());
    });
  });

  group('PcCardController', () {
    late PcCardController card;
    setUp(() => card = PcCardController(repo, actions, connection, pcId));
    tearDown(() => card.dispose());

    test('load, connect, end call with reason and note', () async {
      portal.on('GET /computers/$pcId', (_) => detailJson());
      portal.on('POST /calls', (_) => callJson);
      portal.on('POST /calls/$reqId/end', (_) => {'ok': true});
      await card.load();
      expect(card.call!.requestId, reqId);
      final o = await card.connect();
      expect(o, isA<Connected>());
      expect(launcher.opened, ['123456789']);
      expect(await card.endCall(reasonId: 'rs1', note: 'حل شد'), isTrue);
      expect(card.notice, 'تماس بسته شد.');
      expect(portal.body(portal.sent('POST /calls/$reqId/end').single), {'reasonId': 'rs1', 'note': 'حل شد'});
    });

    test('held by another: the outcome for the question, nothing opened', () async {
      portal.on('GET /computers/$pcId', (_) => detailJson(withCall: false));
      portal.on('POST /calls', (_) => FakePortal.error(409, 'in_session_other', 'x', {'holderName': 'رضا'}));
      await card.load();
      final o = await card.connect();
      expect(o, isA<HeldByOther>());
      expect(launcher.opened, isEmpty);
      expect(card.busy, isFalse);
    });

    test('waiting code-mode call, then the code', () async {
      portal.on('GET /computers/$pcId', (_) => detailJson());
      portal.on('POST /calls', (_) => {...callJson, 'consentMode': 'code', 'waiting': true, 'authorizedUntil': null});
      await card.load();
      await card.connect();
      expect(card.waitingForCode, isNotNull);
      final o = await card.openWithCode('ab12cd');
      expect(o, isA<Connected>());
      expect(card.waitingForCode, isNull);
    });

    test('refusal and portal away become Persian errors', () async {
      portal.on('GET /computers/$pcId', (_) => detailJson());
      await card.load();
      portal.on('POST /calls', (_) => FakePortal.error(403, 'inactive', 'حساب شما غیرفعال است؛ با مدیر تماس بگیرید.'));
      await card.connect();
      expect(card.error, 'حساب شما غیرفعال است؛ با مدیر تماس بگیرید.');
      portal.on('POST /calls', (_) => throw const SocketException('refused'));
      await card.connect();
      expect(card.error, kMsgPortalDown);
      expect(connection.offline, isTrue);
    });

    test('reason, note, message, favourite; no call means nothing is sent', () async {
      portal.on('GET /computers/$pcId', (_) => detailJson());
      for (final r in ['reason', 'note', 'message']) {
        portal.on('POST /calls/$reqId/$r', (_) => {'ok': true});
      }
      portal.on('POST /computers/$pcId/favorite', (_) => {'favorite': true});
      await card.load();
      expect(await card.setReason('rs1'), isTrue);
      expect(await card.addNote('داخلی'), isTrue);
      expect(await card.sendMessage('سلام'), isTrue);
      await card.toggleFavorite();
      expect(card.detail!.computer.favorite, isTrue);

      portal.on('GET /computers/$pcId', (_) => detailJson(withCall: false));
      await card.load();
      final before = portal.requests.length;
      expect(await card.addNote('x'), isFalse);
      expect(portal.requests.length, before);
    });
  });

  group('RequestsController', () {
    late RequestsController reqs;
    setUp(() => reqs = RequestsController(repo, connection));
    tearDown(() => reqs.dispose());

    Map<String, dynamic> row(String id) => {
          'id': id,
          'number': 1,
          'subject': 's',
          'status': 'submitted',
          'priority': 'normal',
          'openedBy': 'customer',
          'kind': 'support',
          'organization': orgA,
          'mine': false,
          'createdAt': '2026-11-14T09:00:00.000Z',
        };

    test('scope, counts, paging', () async {
      portal.on('GET /requests', (r) => r.url.queryParameters['cursor'] == '2'
          ? {'rows': [row('b')], 'next': null, 'counts': {'queue': 2, 'mine': 0}}
          : {'rows': [row('a')], 'next': '2', 'counts': {'queue': 2, 'mine': 0}});
      await reqs.load();
      expect(reqs.queueCount, 2);
      expect(reqs.hasMore, isTrue);
      await reqs.loadMore();
      expect(reqs.rows.map((r) => r.id), ['a', 'b']);
      reqs.setScope(RequestScope.mine);
      await settle();
      expect(portal.requests.last.url.queryParameters['scope'], 'mine');
    });

    test('take: a colleague was quicker', () async {
      portal.on('GET /requests', (_) => {'rows': [], 'next': null, 'counts': {'queue': 0, 'mine': 0}});
      portal.on('POST /requests/$reqId/take', (_) => FakePortal.error(409, 'taken', 'این درخواست دیگر در صف نیست.'));
      expect(await reqs.take(reqId), isFalse);
      expect(reqs.error, 'این درخواست دیگر در صف نیست.');
      portal.on('POST /requests/$reqId/take', (_) => {'ok': true});
      expect(await reqs.take(reqId), isTrue);
      expect(reqs.notice, 'درخواست برداشته شد.');
    });
  });

  group('NotificationsController and ConfigController', () {
    test('newest first, unread count, mark read, capped', () async {
      var n = 0;
      portal.on('GET /notifications', (_) {
        n++;
        return [
          {'id': 'n$n', 'kind': 'callback', 'title': 't', 'body': 'b', 'at': DateTime.utc(2026, 11, 14, 10, n).toIso8601String()}
        ];
      });
      final poller = NotificationPoller(api);
      final notes = NotificationsController(poller, max: 2);
      await poller.poll();
      await poller.poll();
      await poller.poll();
      await settle();
      expect(notes.items.map((x) => x.id), ['n3', 'n2']);
      expect(notes.unread, 2);
      notes.markAllRead();
      expect(notes.unread, 0);
      notes.clear();
      expect(notes.items, isEmpty);
      notes.dispose();
      poller.dispose();
    });

    test('config: reasons; an error is kept in Persian', () async {
      portal.on('GET /config', (_) => {
            'switches': {},
            'theme': null,
            'latest': null,
            'callReasons': [
              {'id': 'rs1', 'name': 'چاپگر'}
            ]
          });
      final cfg = ConfigController(repo, connection);
      await cfg.load();
      expect(cfg.callReasons.single.name, 'چاپگر');
      portal.on('GET /config', (_) => FakePortal.error(500, 'server', 'خطای سرور؛ چند لحظه بعد دوباره امتحان کنید.'));
      await cfg.load();
      expect(cfg.error, 'خطای سرور؛ چند لحظه بعد دوباره امتحان کنید.');
      expect(cfg.value, isNotNull); // the last good config stays
    });
  });

  test('errorText', () {
    expect(errorText(const ApiError(400, 'invalid', 'پیام')), 'پیام');
    expect(errorText(const PortalUnreachable(OfflineReason.slow)), kMsgPortalSlow);
    expect(errorText(StateError('x')), kMsgServer);
  });
}
