import 'dart:io';

import 'package:flutter_hbb/dolphin/tech/actions.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/cache.dart';
import 'package:flutter_hbb/dolphin/tech/notifications.dart';
import 'package:flutter_hbb/dolphin/tech/repository.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_portal.dart';

const pcId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const reqId = '22222222-2222-4222-8222-222222222222';
const pc = PcRef(pcId, '123456789', 'پذیرش');

class FakeLauncher implements SessionLauncher {
  final opened = <(String, String?)>[];
  String id = '987654321';
  List<String> recents = const [];
  bool fail = false;
  @override
  Future<void> open(String rustdeskId, {String? password}) async {
    if (fail) throw StateError('no window');
    opened.add((rustdeskId, password));
  }

  @override
  Future<String> myId() async => id;
  @override
  Future<List<String>> recentIds({int limit = 5}) async => recents.take(limit).toList();
}

class FakeDemo implements DemoStarter {
  final targets = <DemoTarget>[];
  @override
  Future<void> startDemo(DemoTarget target) async => targets.add(target);
}

Map<String, dynamic> noteJson(String id, int minute, {String kind = 'request'}) =>
    {'id': id, 'kind': kind, 'title': 't', 'body': 'b', 'at': DateTime.utc(2026, 11, 14, 10, minute).toIso8601String()};

void main() {
  late FakePortal portal;
  late ApiClient api;
  late FakeLauncher launcher;
  late TechActions actions;
  final registered = <String>[];

  setUp(() {
    portal = FakePortal();
    api = apiOn(portal);
    launcher = FakeLauncher();
    registered.clear();
    actions = TechActions(api, launcher, onIdRegistered: (id) async => registered.add(id));
  });

  group('connect', () {
    test('opens the call on the portal, then the remote window to the PC\'s ID', () async {
      portal.on('POST /calls', (_) => callJson);
      final o = await actions.connect(pc);
      expect(o, isA<Connected>().having((c) => c.call.requestId, 'request', reqId));
      expect(portal.body(portal.sent('POST /calls').single), {'deviceId': pcId});
      expect(launcher.opened, [('123456789', null)]);
    });

    test('another technician\'s session: HeldByOther, nothing opened; takeover sends takeover:true', () async {
      portal.onSeq('POST /calls', [
        (_) => FakePortal.error(409, 'in_session_other', 'این رایانه در جلسه با رضا است.', {'holderName': 'رضا'}),
        (_) => callJson,
      ]);
      final o = await actions.connect(pc);
      expect(o, isA<HeldByOther>().having((h) => h.holderName, 'holder', 'رضا'));
      expect(launcher.opened, isEmpty);
      final o2 = await actions.connect(pc, takeover: true);
      expect(o2, isA<Connected>());
      expect(portal.body(portal.sent('POST /calls').last), {'deviceId': pcId, 'takeover': true});
      expect(launcher.opened, hasLength(1));
    });

    test('a waiting code-mode call does not open until the code is given', () async {
      portal.on('POST /calls', (_) => {...callJson, 'authorizedUntil': null, 'consentMode': 'code', 'waiting': true});
      final o = await actions.connect(pc);
      expect(o, isA<WaitingForCode>());
      expect(launcher.opened, isEmpty);
      final bad = await actions.openWithCode(pc, (o as WaitingForCode).call, 'کد');
      expect(bad, isA<Refused>().having((r) => r.error.message, 'm', kMsgCodeFormat));
      final ok = await actions.openWithCode(pc, o.call, ' ab12 cd ');
      expect(ok, isA<Connected>());
      expect(launcher.opened, [('123456789', 'ab12cd')]);
    });

    test('a code typed up front (click mode, read on the phone) goes to the session', () async {
      portal.on('POST /calls', (_) => callJson);
      await actions.connect(pc, password: 'XY12-34');
      expect(launcher.opened, [('123456789', 'XY1234')]);
    });

    test('a malformed code or ID is refused before the portal is asked', () async {
      expect(await actions.connect(pc, password: '12'), isA<Refused>());
      expect(await actions.connect(const PcRef(pcId, 'bad id!')), isA<Refused>());
      expect(portal.requests, isEmpty);
    });

    test('technician_id_missing: registers this app\'s ID and tries once more', () async {
      portal.onSeq('POST /calls', [
        (_) => FakePortal.error(409, 'technician_id_missing', 'شناسه‌ی دلفین کانکتِ این برنامه هنوز برای شما ثبت نشده است.'),
        (_) => callJson,
      ]);
      portal.on('POST /me/rustdesk-id', (_) => {'ok': true});
      final o = await actions.connect(pc);
      expect(o, isA<Connected>());
      expect(portal.body(portal.sent('POST /me/rustdesk-id').single), {'rustdeskId': '987654321'});
      expect(registered, ['987654321']);
      expect(portal.sent('POST /calls'), hasLength(2));
    });

    test('technician_id_missing and the ID cannot be registered: the original refusal', () async {
      portal.on('POST /calls', (_) => FakePortal.error(409, 'technician_id_missing', 'ثبت نشده'));
      portal.on('POST /me/rustdesk-id', (_) => FakePortal.error(409, 'live_session', 'جلسه‌ای از شما باز است'));
      final o = await actions.connect(pc);
      expect(o, isA<Refused>().having((r) => r.error.code, 'c', 'technician_id_missing'));
      expect(portal.sent('POST /calls'), hasLength(1));
    });

    test('refusals and portal away', () async {
      portal.on('POST /calls', (_) => FakePortal.error(409, 'not_linked', 'این رایانه به سازمانی وصل نیست.'));
      expect(await actions.connect(pc), isA<Refused>().having((r) => r.error.message, 'm', 'این رایانه به سازمانی وصل نیست.'));
      portal.on('POST /calls', (_) => throw const SocketException('refused'));
      expect(await actions.connect(pc), isA<PortalAway>());
      expect(launcher.opened, isEmpty);
    });

    test('the window failing to open is LaunchFailed (the call stays open)', () async {
      portal.on('POST /calls', (_) => callJson);
      launcher.fail = true;
      expect(await actions.connect(pc), isA<LaunchFailed>());
    });

    test('offline connect opens the window without a call; a bad ID does nothing', () async {
      expect(await actions.connectOffline('123456789'), isTrue);
      expect(await actions.connectOffline('x'), isFalse);
      expect(launcher.opened, [('123456789', null)]);
      expect(portal.requests, isEmpty);
    });
  });

  group('demo', () {
    test('POST /demo, then the DemoStarter gets the PC and the call', () async {
      final demo = FakeDemo();
      final a = TechActions(api, launcher, demoStarter: demo);
      portal.on('POST /demo', (_) => callJson);
      final o = await a.demo(pc);
      expect(o, isA<Connected>());
      expect(demo.targets.single.rustdeskId, '123456789');
      expect(demo.targets.single.requestId, reqId);
      expect(demo.targets.single.authorizedUntil, DateTime.utc(2026, 11, 14, 12));
      expect(launcher.opened, isEmpty); // a demo is not a normal session
    });

    test('without a starter yet: LaunchFailed', () async {
      portal.on('POST /demo', (_) => callJson);
      expect(await actions.demo(pc), isA<LaunchFailed>());
    });
  });

  group('ensureMyId', () {
    test('registers only when the portal has another ID', () async {
      portal.on('POST /me/rustdesk-id', (_) => {'ok': true});
      expect(await actions.ensureMyId(const StaffInfo(id: 's', name: 'ع', role: StaffRole.technician, rustdeskId: '987654321')), isNull);
      expect(portal.requests, isEmpty);
      expect(await actions.ensureMyId(const StaffInfo(id: 's', name: 'ع', role: StaffRole.technician)), isNull);
      expect(portal.requests, hasLength(1));
    });

    test('a refusal comes back in Persian', () async {
      portal.on('POST /me/rustdesk-id', (_) => FakePortal.error(409, 'taken', 'این شناسه برای کارشناس دیگری ثبت شده است.'));
      expect(await actions.ensureMyId(const StaffInfo(id: 's', name: 'ع', role: StaffRole.technician)),
          'این شناسه برای کارشناس دیگری ثبت شده است.');
    });
  });

  group('call actions and recent', () {
    test('end with reason and note, snippet used', () async {
      portal.on('POST /calls/$reqId/end', (_) => {'ok': true});
      portal.on('POST /snippets/n1/used', (_) => {'ok': true});
      await actions.endCall(reqId, reasonId: 'rs1', note: 'حل شد');
      await actions.snippetUsed('n1', '123456789');
      expect(portal.body(portal.requests[0]), {'reasonId': 'rs1', 'note': 'حل شد'});
      expect(portal.body(portal.requests[1]), {'rustdeskId': '123456789'});
    });

    test('recent: the app\'s own IDs joined with the known PCs, duplicates and bad IDs dropped', () async {
      launcher.recents = ['123456789', 'bad id', '555666777', '123456789'];
      final known = [Computer.fromJson(pcJson(pcId))];
      final r = await actions.recent(known);
      expect(r.map((x) => x.rustdeskId), ['123456789', '555666777']);
      expect(r.first.displayName, 'پذیرش');
      expect(r.last.computer, isNull);
      expect(r.last.displayName, '555666777');
    });

    test('recent from the offline cache', () async {
      launcher.recents = ['123456789'];
      final snap = OfflineSnapshot([CachedComputer.of(Computer.fromJson(pcJson(pcId)))], DateTime(2026));
      final r = await actions.recentOffline(snap);
      expect(r.single.computer!.fromCache, isTrue);
    });
  });

  group('repository', () {
    late OfflineCache cache;
    late TechRepository repo;
    setUp(() {
      cache = OfflineCache(MemoryBox());
      repo = TechRepository(api, cache);
    });

    test('the unfiltered list refreshes the cache; filtered lists do not', () async {
      portal.on('GET /computers', (r) => r.url.queryParameters['cursor'] == '2'
          ? pageJson([pcJson('b', rustdeskId: '222333444')])
          : pageJson([pcJson('a')], next: '2'));
      await repo.computers(const ComputerQuery());
      expect((await cache.load())!.items.map((c) => c.id), ['a']);
      await repo.computers(const ComputerQuery(), cursor: '2');
      expect((await cache.load())!.items.map((c) => c.id), ['a', 'b']);
      await repo.computers(const ComputerQuery(q: 'x'));
      await repo.computers(const ComputerQuery(view: PcView.online));
      expect((await cache.load())!.items.map((c) => c.id), ['a', 'b']);
      final off = await repo.offlineComputers(const ComputerQuery(q: '222'));
      expect(off!.items.map((c) => c.id), ['b']);
    });

    test('favourite updates the cache with what the portal saved', () async {
      await cache.save([Computer.fromJson(pcJson(pcId))]);
      portal.on('POST /computers/$pcId/favorite', (_) => {'favorite': true});
      expect(await repo.setFavorite(pcId, true), isTrue);
      expect((await cache.load())!.items.single.favorite, isTrue);
    });

    test('snippets and config are held until refreshed or reset', () async {
      portal.on('GET /snippets', (_) => {'rows': []});
      portal.on('GET /config', (_) => {'switches': {}, 'theme': null, 'latest': null, 'callReasons': []});
      await repo.snippets();
      await repo.snippets();
      expect(portal.sent('GET /snippets'), hasLength(1));
      await repo.snippets(refresh: true);
      expect(portal.sent('GET /snippets'), hasLength(2));
      expect(repo.config, isNull);
      await repo.loadConfig();
      expect(repo.config, isNotNull);
      repo.reset();
      expect(repo.config, isNull);
    });

    test('debouncer runs only the last call', () async {
      final d = Debouncer(const Duration(milliseconds: 20));
      var runs = <int>[];
      for (var i = 0; i < 5; i++) {
        d(() => runs.add(i));
      }
      expect(d.pending, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(runs, [4]);
      runs = [];
      d(() => runs.add(1));
      d.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(runs, isEmpty);
    });
  });

  group('notifications poller', () {
    late NotificationPoller poller;
    setUp(() => poller = NotificationPoller(api, interval: const Duration(milliseconds: 20)));
    tearDown(() => poller.dispose());

    test('dedupe by id, since moves to the last at, new items on the stream', () async {
      portal.onSeq('GET /notifications', [
        (_) => [noteJson('a', 1), noteJson('b', 2)],
        (_) => [noteJson('b', 2), noteJson('c', 3)],
        (_) => <Object>[],
      ]);
      final got = <String>[];
      poller.items.listen((n) => got.add(n.id));
      expect((await poller.poll()).map((n) => n.id), ['a', 'b']);
      expect(portal.requests.last.url.queryParameters.containsKey('since'), isFalse);
      expect((await poller.poll()).map((n) => n.id), ['c']);
      expect(portal.requests.last.url.queryParameters['since'], '2026-11-14T10:02:00.000Z');
      await poller.poll();
      expect(portal.requests.last.url.queryParameters['since'], '2026-11-14T10:03:00.000Z');
      await settle();
      expect(got, ['a', 'b', 'c']);
    });

    test('network trouble is quiet; the next poll tries again', () async {
      portal.onSeq('GET /notifications', [
        (_) => throw const SocketException('down'),
        (_) => throw const SocketException('down'),
        (_) => [noteJson('a', 1)],
      ]);
      expect(await poller.poll(), isEmpty);
      expect(poller.answeredPolls, 0);
      expect((await poller.poll()).single.id, 'a');
      expect(poller.answeredPolls, 1);
    });

    test("answeredPolls: the first answer's items are delivered while it is 1, later ones after it moved on", () async {
      portal.onSeq('GET /notifications', [
        (_) => [noteJson('a', 1), noteJson('b', 2)],
        (_) => [noteJson('c', 3)],
      ]);
      final seenAt = <String, int>{};
      poller.items.listen((n) => seenAt[n.id] = poller.answeredPolls);
      await poller.poll();
      await settle();
      await poller.poll();
      await settle();
      expect(seenAt, {'a': 1, 'b': 1, 'c': 2});
      poller.reset();
      expect(poller.answeredPolls, 0);
    });

    test('an expired sign-in stops polling', () async {
      portal.on('GET /notifications', (_) => FakePortal.error(401, 'expired', 'تمام شد'));
      poller.start();
      expect(poller.running, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(poller.running, isFalse);
    });

    test('start polls at once and on the interval; reset forgets what was seen', () async {
      portal.on('GET /notifications', (_) => [noteJson('a', 1)]);
      final got = <String>[];
      poller.items.listen((n) => got.add(n.id));
      poller.start();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      poller.stop();
      expect(portal.sent('GET /notifications').length, greaterThanOrEqualTo(3));
      expect(got, ['a']);
      poller.reset();
      expect(poller.since, isNull);
      await poller.poll();
      await settle();
      expect(got, ['a', 'a']);
    });
  });
}
