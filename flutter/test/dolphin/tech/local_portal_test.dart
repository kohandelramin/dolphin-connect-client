import 'dart:io';

import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/cache.dart';
import 'package:flutter_hbb/dolphin/tech/repository.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_hbb/dolphin/tech/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in: against the local dev portal (Docker, `main` with the App API), read only. Run with
///   DOLPHIN_LOCAL_PORTAL=http://localhost:3010 flutter test test/dolphin/tech/local_portal_test.dart
/// Signs in as the local seed's admin, lists computers, reads config and notifications, signs out.
void main() {
  final portalUrl = Platform.environment['DOLPHIN_LOCAL_PORTAL'];
  final skip = portalUrl == null || portalUrl.isEmpty ? 'set DOLPHIN_LOCAL_PORTAL to run against the local portal' : null;

  test('sign in to the local portal and list computers', () async {
    final api = ApiClient(portalUrl: portalUrl);
    final cache = OfflineCache(MemoryBox());
    final store = SessionStore(api, MemoryBox(), cache: cache);
    final repo = TechRepository(api, cache);
    addTearDown(api.close);

    expect(await store.signIn('admin.local', 'a-long-password-1'), isTrue, reason: store.error);
    expect(store.staff!.role, StaffRole.admin);
    expect(store.expiresAt!.isAfter(DateTime.now()), isTrue);

    final page = await repo.computers(const ComputerQuery());
    // ignore: avoid_print
    print('local portal: ${page.rows.length} computers on the first page (matching ${page.counts.matching}, '
        'online ${page.counts.online}, starred ${page.counts.favorite}), next ${page.next}');
    expect(page.counts.matching, greaterThanOrEqualTo(page.rows.length));
    final cached = await cache.load();
    expect(cached!.items.length, page.rows.length);

    final config = await repo.loadConfig();
    // ignore: avoid_print
    print('local portal: config with ${config.callReasons.length} call reasons, latest ${config.latest?.version}');
    final notes = await api.notifications();
    // ignore: avoid_print
    print('local portal: ${notes.length} notifications without since');
    final reqs = await repo.requests(RequestScope.queue);
    // ignore: avoid_print
    print('local portal: queue ${reqs.queueCount}, mine ${reqs.mineCount}');

    if (page.rows.isNotEmpty) {
      final d = await repo.computer(page.rows.first.id);
      final h = await repo.deviceHistory(page.rows.first.id);
      // ignore: avoid_print
      print('local portal: card of ${d.computer.displayName}: call ${d.call != null}, ${d.history.length} contacts, '
          '${d.sentToday.length} sent today; history ${h.length}');
    }
    final orgs = await repo.organizations();
    if (orgs.rows.isNotEmpty) await repo.organization(orgs.rows.first.id);
    final closed = await repo.requests(RequestScope.closed);
    final snippets = await repo.snippets();
    // ignore: avoid_print
    print('local portal: ${orgs.rows.length} organizations, ${closed.rows.length} closed, ${snippets.length} snippets');

    await store.signOut();
    expect(store.state, SignInState.signedOut);
    expect(await cache.load(), isNull);
    // The token is gone on the portal too: a stale token answers 401 expired.
  }, skip: skip, timeout: const Timeout(Duration(minutes: 1)));
}
