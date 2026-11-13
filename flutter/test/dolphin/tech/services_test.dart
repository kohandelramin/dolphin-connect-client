import 'package:flutter_hbb/dolphin/tech/actions.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech/secret_box.dart';
import 'package:flutter_hbb/dolphin/tech/services.dart';
import 'package:flutter_hbb/dolphin/tech/session_store.dart';
import 'package:flutter_hbb/dolphin/tech/state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_portal.dart';

class FakeLauncher implements SessionLauncher {
  @override
  Future<void> open(String rustdeskId, {String? password}) async {}
  @override
  Future<String> myId() async => '111222333';
  @override
  Future<List<String>> recentIds({int limit = 5}) async => const [];
}

void main() {
  test('sign in, register the ID, poll, sign out clears everything', () async {
    final portal = FakePortal();
    portal.on('POST /login', (_) => {
          'token': 'tok-secret-123',
          'expiresAt': DateTime.now().add(const Duration(hours: 8)).toUtc().toIso8601String(),
          'staff': {'id': 's1', 'name': 'علی', 'role': 'technician', 'rustdeskId': null},
        });
    portal.on('POST /me/rustdesk-id', (_) => {'ok': true});
    portal.on('GET /notifications', (_) => <Object>[]);
    portal.on('GET /computers', (_) => pageJson([pcJson('a')]));
    portal.on('POST /logout', (_) => {'ok': true});
    final sessionBox = MemoryBox();
    final offlineBox = MemoryBox();
    final s = TechServices(
      api: ApiClient(portalUrl: 'http://portal.test', client: portal.client, probe: FixedProbe()),
      sessionBox: sessionBox,
      offlineBox: offlineBox,
      launcher: FakeLauncher(),
      prefs: MemoryPrefs(),
    );
    expect(await s.session.signIn('admin.local', 'pw'), isTrue);
    expect(await s.afterSignIn(), isNull);
    expect(s.session.staff!.rustdeskId, '111222333');
    expect(s.poller.running, isTrue);
    final dash = s.dashboard();
    await dash.load();
    expect(await offlineBox.read(), isNotNull);
    await s.signOut();
    expect(s.session.state, SignInState.signedOut);
    expect(s.poller.running, isFalse);
    expect(await sessionBox.read(), isNull);
    expect(await offlineBox.read(), isNull);
    dash.dispose();
    s.dispose();
  });
}
