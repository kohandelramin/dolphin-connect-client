import 'dart:io';

import 'package:flutter_hbb/dolphin/tech/actions.dart';
import 'package:flutter_hbb/dolphin/tech/api.dart';
import 'package:flutter_hbb/dolphin/tech_ui/code_wait.dart';
import 'package:flutter_hbb/dolphin/tech_ui/updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'harness.dart';

class FakeInstaller implements UpdateInstaller {
  final staged = <(String, String, String, int)>[];
  int applied = 0;
  InstallProgress afterStage = const InstallProgress('ready');
  InstallProgress afterApply = const InstallProgress('applying', text: 'در حال نصب…');

  @override
  Future<void> stage(File file, LatestRelease r) async {
    staged.add((await file.readAsString(), r.version, r.sha256, r.size));
  }

  @override
  Future<void> apply() async => applied++;

  @override
  Future<InstallProgress> progress() async => applied > 0 ? afterApply : afterStage;
}

void main() {
  group('code mode (TB-21)', () {
    test('while the call waits it asks every few seconds; the code that arrives opens the session once', () async {
      final portal = samplePortal();
      final launcher = RecLauncher();
      final s = servicesOn(portal, launcher: launcher);
      await signIn(s);
      portal.onSeq('GET /computers/pc-1', [
        (_) => detailJson(samplePcs.first, call: callJson2(consent: 'code', waitingForCode: true)),
        (_) => detailJson(samplePcs.first, call: callJson2(consent: 'code', waitingForCode: true)),
        (_) => detailJson(samplePcs.first, call: callJson2(consent: 'code', code: 'k7m2p9')),
        (_) => detailJson(samplePcs.first, call: callJson2(consent: 'code', code: 'k7m2p9', live: true)),
      ]);
      final card = s.card('pc-1');
      final outcomes = <ConnectOutcome>[];
      final w = CodeModeWatcher(card, every: const Duration(milliseconds: 20), onOutcome: outcomes.add);
      await card.load();
      expect(w.waiting, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(launcher.opened, [('194052361', 'k7m2p9')]);
      expect(outcomes.single, isA<Connected>());
      final polls = portal.sent('GET /computers/pc-1').length;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(portal.sent('GET /computers/pc-1').length, lessThanOrEqualTo(polls + 1), reason: 'polling stopped');
      expect(launcher.opened, hasLength(1), reason: 'the code is used once');
      w.dispose();
      card.dispose();
      s.dispose();
    });

    test('a code typed by hand still works; a malformed one is refused in Persian', () async {
      final portal = samplePortal();
      final launcher = RecLauncher();
      final s = servicesOn(portal, launcher: launcher);
      await signIn(s);
      portal.on('GET /computers/pc-1', (_) => detailJson(samplePcs.first, call: callJson2(consent: 'code', waitingForCode: true)));
      final card = s.card('pc-1');
      final w = CodeModeWatcher(card, every: const Duration(seconds: 30));
      await card.load();
      expect(await w.typed('ab'), isA<Refused>());
      expect(card.error, kMsgCodeFormat);
      expect(await w.typed('K7M 2P9'), isA<Connected>());
      expect(launcher.opened.single, ('194052361', 'K7M2P9'));
      w.dispose();
      card.dispose();
      s.dispose();
    });

    test('click mode never polls', () async {
      final portal = samplePortal();
      final s = servicesOn(portal);
      await signIn(s);
      portal.on('GET /computers/pc-1', (_) => detailJson(samplePcs.first, call: callJson2()));
      final card = s.card('pc-1');
      final w = CodeModeWatcher(card, every: const Duration(milliseconds: 10));
      await card.load();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(portal.sent('GET /computers/pc-1'), hasLength(1));
      expect(w.waiting, isFalse);
      w.dispose();
      card.dispose();
      s.dispose();
    });
  });

  group('the technician update through the app API', () {
    const release = LatestRelease('2.2.0', '/api/app/v1/download/technician', 'aaaa', 3);

    test('downloads with the staff token, stages with the portal\'s values, then installs', () async {
      final portal = samplePortal();
      portal.on('GET /download/technician', (_) => http.Response('exe', 200));
      final s = servicesOn(portal);
      await signIn(s);
      final inst = FakeInstaller();
      final u = TechUpdater(s.api, inst, poll: const Duration(milliseconds: 5));
      final run = u.run(release);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(portal.sent('GET /download/technician').single.headers['Authorization'], 'Bearer tok-secret-123');
      expect(inst.staged.single, ('exe', '2.2.0', 'aaaa', 3));
      expect(inst.applied, 1);
      expect(u.phase, TechUpdatePhase.installing);
      u.dispose();
      await run;
      s.dispose();
    });

    test('the install waits while a session window is open', () async {
      final portal = samplePortal();
      portal.on('GET /download/technician', (_) => http.Response('exe', 200));
      final s = servicesOn(portal);
      await signIn(s);
      final inst = FakeInstaller();
      var open = true;
      final u = TechUpdater(s.api, inst, sessionsOpen: () => open, poll: const Duration(milliseconds: 5));
      final run = u.run(release);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(u.phase, TechUpdatePhase.waitingSessions);
      expect(u.text, kUpdateWaitingSessions);
      expect(inst.applied, 0);
      open = false;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(inst.applied, 1);
      u.dispose();
      await run;
      s.dispose();
    });

    test('a refused download, a wrong size, a refused stage and a failed swap each end in Persian', () async {
      final portal = samplePortal();
      final s = servicesOn(portal);
      await signIn(s);
      final inst = FakeInstaller();
      final u = TechUpdater(s.api, inst, poll: const Duration(milliseconds: 5));

      portal.on('GET /download/technician', (_) => FakePortal.error(403, 'forbidden', 'این بخش فقط برای کارشناسان دلفین است.'));
      await u.run(release);
      expect(u.phase, TechUpdatePhase.failed);
      expect(u.error, 'این بخش فقط برای کارشناسان دلفین است.');

      portal.on('GET /download/technician', (_) => http.Response('too long', 200));
      await u.run(release);
      expect(u.error, kMsgBadAnswer);
      expect(inst.staged, isEmpty);

      portal.on('GET /download/technician', (_) => http.Response('exe', 200));
      inst.afterStage = const InstallProgress('failed', error: 'فایل دریافت‌شده با نسخه‌ی دلفین یکی نبود و کنار گذاشته شد.');
      await u.run(release);
      expect(u.error, startsWith('فایل دریافت‌شده'));
      expect(inst.applied, 0);

      inst.afterStage = const InstallProgress('ready');
      inst.afterApply = const InstallProgress('failed', error: 'برای نصب نسخه‌ی تازه اجازه‌ی مدیر ویندوز لازم است.');
      await u.run(release);
      expect(u.error, startsWith('برای نصب'));

      await u.run(null);
      expect(u.error, kUpdateNoRelease);
      u.dispose();
      s.dispose();
    });

    test('the install progress JSON is read as the Rust side writes it', () {
      final p = InstallProgress.fromJson('{"state":"failed","percent":0,"text":"","error":"خطا","waiting":false}');
      expect((p.state, p.error), ('failed', 'خطا'));
      expect(InstallProgress.fromJson('nonsense').state, 'idle');
    });
  });
}
