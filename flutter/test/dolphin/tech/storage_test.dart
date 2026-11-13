import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/cache.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_hbb/dolphin/tech/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_portal.dart';

/// Reverses the bytes: enough to prove the file never holds the plain text, on any platform.
class ReverseSealer implements Sealer {
  @override
  Uint8List seal(Uint8List plain) => Uint8List.fromList(plain.reversed.toList());
  @override
  Uint8List? open(Uint8List sealed) => sealed.isEmpty ? null : Uint8List.fromList(sealed.reversed.toList());
}

Computer pc(String id, {bool favorite = false, List<String> tags = const ['حسابداری'], String? label = 'پذیرش', String rid = '123456789'}) =>
    Computer.fromJson(pcJson(id, favorite: favorite, tags: tags, label: label, rustdeskId: rid));

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('dc-tech-store'));
  tearDown(() => dir.delete(recursive: true));

  group('DPAPI (Windows)', () {
    test('seal and open round-trip; the sealed bytes are not the plain text', () {
      const s = DpapiSealer();
      final plain = Uint8List.fromList(utf8.encode('{"token":"tok-secret-123"}'));
      final sealed = s.seal(plain);
      expect(utf8.decode(sealed, allowMalformed: true), isNot(contains('tok-secret-123')));
      expect(s.open(sealed), plain);
    }, skip: !Platform.isWindows);

    test('another entropy or a damaged blob does not open', () {
      final sealed = const DpapiSealer().seal(Uint8List.fromList([1, 2, 3]));
      expect(const DpapiSealer([9, 9, 9]).open(sealed), isNull);
      final damaged = Uint8List.fromList(sealed)..[sealed.length - 1] ^= 0xff;
      expect(const DpapiSealer().open(damaged), isNull);
    }, skip: !Platform.isWindows);

    test('a sealed file box on disk', () async {
      final box = SealedFileBox(File('${dir.path}/session'));
      await box.write('tok-secret-123');
      expect(await File('${dir.path}/session').readAsString().catchError((_) => ''), isNot(contains('tok-secret-123')));
      expect(await box.read(), 'tok-secret-123');
      await box.clear();
      expect(await box.read(), isNull);
      expect(await File('${dir.path}/session').exists(), isFalse);
    }, skip: !Platform.isWindows);
  });

  group('SealedFileBox', () {
    test('write, read, clear; nothing stored reads null', () async {
      final box = SealedFileBox(File('${dir.path}/sub/box'), sealer: ReverseSealer());
      expect(await box.read(), isNull);
      await box.write('hello');
      expect(await File('${dir.path}/sub/box').readAsString(), 'olleh');
      expect(await box.read(), 'hello');
      await box.clear();
      expect(await box.read(), isNull);
    });

    test('a file that does not open reads null', () async {
      final f = File('${dir.path}/box')..writeAsBytesSync([]);
      expect(await SealedFileBox(f, sealer: ReverseSealer()).read(), isNull);
    });
  });

  group('offline cache (TD-2)', () {
    test('save keeps only the tile fields, with lastUpdated', () async {
      final box = MemoryBox();
      final cache = OfflineCache(box, now: () => DateTime.utc(2026, 11, 14, 7, 12));
      await cache.save([pc('a', favorite: true)]);
      final raw = jsonDecode((await box.read())!) as Map<String, dynamic>;
      final item = (raw['items'] as List).single as Map<String, dynamic>;
      expect(item.keys.toSet(), {'id', 'rustdeskId', 'hostname', 'label', 'orgName', 'orgColor', 'tags', 'favorite'});
      final snap = (await cache.load())!;
      expect(snap.lastUpdated.toUtc(), DateTime.utc(2026, 11, 14, 7, 12));
      final c = snap.items.single;
      expect(c.favorite, isTrue);
      expect(c.orgName, 'گردش‌کار');
      expect(c.orgColor, '#1d4ed8');
      final row = c.toComputer();
      expect(row.fromCache, isTrue);
      expect(row.online, isFalse);
      expect(row.lastSeenAt, isNull);
      expect(row.session, isNull);
    });

    test('append adds a page and replaces PCs already there', () async {
      final cache = OfflineCache(MemoryBox());
      await cache.save([pc('a'), pc('b')]);
      await cache.append([pc('b', label: 'تازه'), pc('c')]);
      final items = (await cache.load())!.items;
      expect(items.map((c) => c.id), ['a', 'b', 'c']);
      expect(items[1].label, 'تازه');
    });

    test('setFavorite keeps the cached star in step', () async {
      final cache = OfflineCache(MemoryBox());
      await cache.save([pc('a'), pc('b')]);
      await cache.setFavorite('b', true);
      expect((await cache.load())!.items.map((c) => c.favorite), [false, true]);
    });

    test('clear, another version and damaged data read as no cache', () async {
      final box = MemoryBox();
      final cache = OfflineCache(box);
      await cache.save([pc('a')]);
      await cache.clear();
      expect(await cache.load(), isNull);
      await box.write(jsonEncode({'v': 99, 'lastUpdated': '2026-11-14T00:00:00Z', 'items': []}));
      expect(await cache.load(), isNull);
      await box.write('not json');
      expect(await cache.load(), isNull);
      await box.write(jsonEncode({
        'v': 1,
        'lastUpdated': '2026-11-14T00:00:00Z',
        'items': [
          {'id': 'x'},
          CachedComputer.of(pc('a')).toJson()
        ]
      }));
      expect((await cache.load())!.items.map((c) => c.id), ['a']); // the damaged entry is skipped
    });

    test('never more than the cap', () async {
      final cache = OfflineCache(MemoryBox());
      await cache.save([for (var i = 0; i < kOfflineCacheMax + 5; i++) pc('$i')]);
      expect((await cache.load())!.items, hasLength(kOfflineCacheMax));
    });

    test('local filter: search over name, ID, organization and tags; favourites; tag', () {
      final items = [
        CachedComputer.of(pc('a', label: 'پذیرش', rid: '111222333', tags: ['حسابداری'])),
        CachedComputer.of(pc('b', label: 'انبار', rid: '444555666', tags: ['انبار'], favorite: true)),
      ];
      expect(filterCached(items, const ComputerQuery(q: 'انبار')).map((c) => c.id), ['b']);
      expect(filterCached(items, const ComputerQuery(q: '111 222')).map((c) => c.id), ['a']);
      expect(filterCached(items, const ComputerQuery(q: 'گردش')).length, 2);
      expect(filterCached(items, const ComputerQuery(view: PcView.favorite)).map((c) => c.id), ['b']);
      expect(filterCached(items, const ComputerQuery(tag: 'حسابداری')).map((c) => c.id), ['a']);
    });
  });

  group('session store', () {
    late FakePortal portal;
    late ApiClient api;
    late MemoryBox box;
    late MemoryBox cacheBox;
    late OfflineCache cache;
    late SessionStore store;
    final now = DateTime.utc(2026, 11, 14, 10);

    setUp(() {
      portal = FakePortal();
      api = ApiClient(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe());
      box = MemoryBox();
      cacheBox = MemoryBox();
      cache = OfflineCache(cacheBox);
      store = SessionStore(api, box, cache: cache, now: () => now);
      portal.on('POST /login', (_) => {
            'token': 'tok-secret-123',
            'expiresAt': '2026-11-14T18:00:00.000Z',
            'staff': {'id': 's1', 'name': 'علی', 'role': 'admin', 'rustdeskId': '987654321'},
          });
      portal.on('POST /logout', (_) => {'ok': true});
      portal.on('GET /snippets', (_) => {'rows': []});
    });

    test('nothing stored: signed out', () async {
      await store.load();
      expect(store.state, SignInState.signedOut);
      expect(store.signedIn, isFalse);
    });

    test('sign-in keeps the session; the API sends its token; a restart reads it back', () async {
      expect(await store.signIn('admin.local', 'pw'), isTrue);
      expect(store.signedIn, isTrue);
      expect(store.staff!.name, 'علی');
      expect(await box.read(), contains('tok-secret-123'));
      expect(await box.read(), isNot(contains('pw'))); // the password is never kept
      await api.snippets();
      expect(portal.sent('GET /snippets').single.headers['Authorization'], 'Bearer tok-secret-123');

      final again = SessionStore(ApiClient(portalUrl: 'http://portal.test', client: portal.client), box, now: () => now);
      await again.load();
      expect(again.signedIn, isTrue);
      expect(again.staff!.rustdeskId, '987654321');
      expect(again.expiresAt, DateTime.utc(2026, 11, 14, 18));
    });

    test('a wrong password: Persian error, nothing kept', () async {
      portal.on('POST /login', (_) => FakePortal.error(401, 'invalid', 'نام کاربری یا رمز عبور درست نیست.'));
      expect(await store.signIn('a', 'b'), isFalse);
      expect(store.error, 'نام کاربری یا رمز عبور درست نیست.');
      expect(store.state, SignInState.unknown);
      expect(await box.read(), isNull);
    });

    test('empty fields are refused without asking the portal', () async {
      expect(await store.signIn(' ', 'x'), isFalse);
      expect(store.error, isNotNull);
      expect(portal.requests, isEmpty);
    });

    test('portal away at sign-in: the offline text', () async {
      portal.on('POST /login', (_) => throw const SocketException('Connection refused'));
      expect(await store.signIn('a', 'b'), isFalse);
      expect(store.error, kMsgPortalDown);
    });

    test('sign-out ends the session on the portal, forgets the token and clears the offline list', () async {
      await store.signIn('a', 'b');
      await cache.save([pc('a')]);
      await store.signOut();
      expect(portal.sent('POST /logout').single.headers['Authorization'], 'Bearer tok-secret-123');
      expect(store.state, SignInState.signedOut);
      expect(await box.read(), isNull);
      expect(await cache.load(), isNull);
    });

    test('sign-out works offline too', () async {
      await store.signIn('a', 'b');
      portal.on('POST /logout', (_) => throw const SocketException('down'));
      await store.signOut();
      expect(store.state, SignInState.signedOut);
      expect(await box.read(), isNull);
    });

    test('a 401 expired anywhere: expired state, token and cache gone', () async {
      await store.signIn('a', 'b');
      await cache.save([pc('a')]);
      portal.on('GET /snippets', (_) => FakePortal.error(401, 'expired', 'ورود شما تمام شده است؛ دوباره وارد شوید.'));
      await expectLater(api.snippets(), throwsA(isA<SignInExpired>()));
      await settle();
      await settle();
      expect(store.state, SignInState.expired);
      expect(await box.read(), isNull);
      expect(await cache.load(), isNull);
    });

    test('a stored session past its expiry starts as expired', () async {
      await box.write(StoredSession('tok', DateTime.utc(2026, 11, 14, 9), const StaffInfo(id: 's', name: 'ع', role: StaffRole.technician)).toJson());
      await store.load();
      expect(store.state, SignInState.expired);
      expect(await box.read(), isNull);
    });

    test('a damaged stored session is dropped', () async {
      await box.write('{"token": 5}');
      await store.load();
      expect(store.state, SignInState.signedOut);
      expect(await box.read(), isNull);
    });

    test('updateRustdeskId keeps the new ID; toString never shows the token', () async {
      await store.signIn('a', 'b');
      await store.updateRustdeskId('111222333');
      expect(store.staff!.rustdeskId, '111222333');
      expect(StoredSession.tryParse((await box.read())!)!.staff.rustdeskId, '111222333');
      expect(StoredSession.tryParse((await box.read())!).toString(), isNot(contains('tok-secret-123')));
    });
  });
}
