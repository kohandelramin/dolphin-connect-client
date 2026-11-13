import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tech/api.dart';
import '../tech/state.dart' show errorText;

/// Plan 19: the technician update popup's «به‌روزرسانی». The new build is downloaded through the app API with the
/// staff sign-in (D13: the technician file is never on the public page), then handed to the TB-20 install flow
/// (src/dolphin_update.rs `stage_local` → `apply_or_fail`): the same size and SHA-256 check, the same swap and restart.
/// Nothing is installed while a session window is open (the restart would close it).
const kTechDownloadPath = '/api/app/v1/download/technician';

/// The install side (the app's is the native bridge; tests use a fake).
abstract class UpdateInstaller {
  /// Hands over the downloaded file with what the portal said about it.
  Future<void> stage(File file, LatestRelease release);

  /// Starts the swap; on success the app restarts and this never comes back.
  Future<void> apply();

  /// The install's state: idle, ready, applying or failed, with the Persian text and error.
  Future<InstallProgress> progress();
}

class InstallProgress {
  final String state;
  final String text;
  final String error;
  const InstallProgress(this.state, {this.text = '', this.error = ''});

  /// The JSON `dolphin-update-progress` gives (src/dolphin_update.rs `progress`).
  factory InstallProgress.fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const InstallProgress('idle');
      String s(String k) => m[k] is String ? m[k] as String : '';
      return InstallProgress(s('state').isEmpty ? 'idle' : s('state'), text: s('text'), error: s('error'));
    } catch (_) {
      return const InstallProgress('idle');
    }
  }
}

enum TechUpdatePhase { idle, downloading, waitingSessions, installing, failed }

const kUpdateDownloading = 'در حال دریافت نسخه‌ی تازه از پورتال دلفین…';
const kUpdateWaitingSessions = 'نصب تا بسته شدن جلسه‌های باز صبر می‌کند.';
const kUpdateInstalling = 'در حال نصب؛ برنامه خودش دوباره باز می‌شود.';
const kUpdateNoRelease = 'پورتال نسخه‌ی تازه‌ای برای برنامه‌ی کارشناس نمی‌شناسد.';
const kUpdateFailed = 'به‌روزرسانی انجام نشد.';

class TechUpdater extends ChangeNotifier {
  final ApiClient api;
  final UpdateInstaller installer;
  final Future<Directory> Function() tempDir;

  /// True while a session window is open: the install waits.
  final bool Function() sessionsOpen;
  final Duration poll;

  TechUpdater(this.api, this.installer,
      {Future<Directory> Function()? tempDir, bool Function()? sessionsOpen, this.poll = const Duration(milliseconds: 500)})
      : tempDir = tempDir ?? (() => Directory.systemTemp.createTemp('dolphin-update-')),
        sessionsOpen = sessionsOpen ?? (() => false);

  TechUpdatePhase _phase = TechUpdatePhase.idle;
  String _text = '';
  String _error = '';
  bool _disposed = false;

  TechUpdatePhase get phase => _phase;
  String get text => _text;
  String get error => _error;
  bool get running => _phase == TechUpdatePhase.downloading || _phase == TechUpdatePhase.waitingSessions || _phase == TechUpdatePhase.installing;

  void _set(TechUpdatePhase p, {String text = '', String error = ''}) {
    _phase = p;
    _text = text;
    _error = error;
    if (!_disposed) notifyListeners();
  }

  /// Downloads [release] and installs it. Returns when it failed (on success the app restarts first).
  Future<void> run(LatestRelease? release) async {
    if (running) return;
    if (release == null) {
      _set(TechUpdatePhase.failed, error: kUpdateNoRelease);
      return;
    }
    _set(TechUpdatePhase.downloading, text: kUpdateDownloading);
    File? file;
    try {
      final dir = await tempDir();
      file = File('${dir.path}${Platform.pathSeparator}dolphin-connect-technician.exe');
      await api.download(kTechDownloadPath, file, expectedSize: release.size);
    } catch (e) {
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      _set(TechUpdatePhase.failed, error: errorText(e));
      return;
    }
    await installer.stage(file, release);
    final staged = await installer.progress();
    if (staged.state != 'ready') {
      _set(TechUpdatePhase.failed, error: staged.error.isNotEmpty ? staged.error : kUpdateFailed);
      return;
    }
    while (sessionsOpen()) {
      if (_phase != TechUpdatePhase.waitingSessions) _set(TechUpdatePhase.waitingSessions, text: kUpdateWaitingSessions);
      await Future<void>.delayed(poll);
      if (_disposed) return;
    }
    _set(TechUpdatePhase.installing, text: kUpdateInstalling);
    unawaited(installer.apply());
    while (!_disposed) {
      await Future<void>.delayed(poll);
      final p = await installer.progress();
      if (p.state == 'failed') {
        _set(TechUpdatePhase.failed, error: p.error.isNotEmpty ? p.error : kUpdateFailed);
        return;
      }
      if (p.text.isNotEmpty && p.text != _text) _set(TechUpdatePhase.installing, text: p.text);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
