import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../utils/multi_window_manager.dart';
import '../brand.dart';
import '../tech/api.dart' show LatestRelease;
import 'platform.dart';
import 'updater.dart';

/// Plan 19: the running app's side of [TechPlatform] and [UpdateInstaller]. The only tech_ui file that touches the
/// native bridge, the window manager and the session windows; not covered by unit tests (it needs the running app).
/// Nothing here changes how a session connects.
class AppTechPlatform implements TechPlatform {
  AppTechPlatform() {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Timer? _timer;
  bool _polling = false;

  @override
  final ValueNotifier<bool?> serverOnline = ValueNotifier(null);
  @override
  final TechSessions sessions = TechSessions();
  @override
  final TechSettingsStore settings = const _AppSettingsStore();

  /// Every 3 s: the engine server's state (upstream's `status_num`) and the peers of the open session windows
  /// (upstream's `get_remote_list` event, as the window-position code reads them).
  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      try {
        final status = jsonDecode(await bind.mainGetConnectStatus());
        final n = status is Map ? status['status_num'] : null;
        serverOnline.value = n == 1 ? true : (n == -1 ? false : serverOnline.value);
      } catch (_) {}
      final ids = <String>[];
      try {
        for (final w in await rustDeskWinManager.getAllSubWindowIds()) {
          try {
            final list = await DesktopMultiWindow.invokeMethod(w, kWindowEventGetRemoteList, null);
            if (list is String && list.isNotEmpty) ids.addAll(list.split(',').where((s) => s.isNotEmpty));
          } catch (_) {}
        }
      } catch (_) {}
      sessions.update(ids, DateTime.now());
    } finally {
      _polling = false;
    }
  }

  @override
  Future<String> myId() => bind.mainGetMyId();

  @override
  ThemeMode get themeMode => MyTheme.getThemeModePreference();

  /// DD-53: upstream's `theme` option; MyTheme.changeDarkMode also tells the session windows.
  @override
  Future<void> setThemeMode(ThemeMode mode) => MyTheme.changeDarkMode(mode);

  @override
  Future<void> openUrl(String url) async {
    await launchUrl(Uri.parse(url));
  }

  @override
  Future<void> copy(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<bool> appInFront() async {
    try {
      return await windowManager.isFocused() && !await windowManager.isMinimized() && await windowManager.isVisible();
    } catch (_) {
      return true;
    }
  }

  /// UN-16: a Windows notice with its sound, shown by this same program started with one argument (src/core_main.rs
  /// `--dolphin-notify`); it exits after. A click on it does not open the app (the notice belongs to Windows' own
  /// sender); the in-app notice and the bell list open the PC or request.
  @override
  Future<void> systemToast(String text) async {
    try {
      await Process.start(Platform.resolvedExecutable, ['--dolphin-notify', text], mode: ProcessStartMode.detached);
    } catch (_) {}
  }

  @override
  Future<Directory> downloadsDir() async {
    final base = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}Dolphin Connect');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<void> openFolder(String path) async {
    await launchUrl(Uri.file(path));
  }

  @override
  Future<bool> focusSession(String rustdeskId) async {
    try {
      for (final w in await rustDeskWinManager.getAllSubWindowIds()) {
        final ok = await DesktopMultiWindow.invokeMethod(w, kWindowEventActiveSession, rustdeskId);
        if (ok == true) return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  String get version => DolphinBrand.version;

  void dispose() {
    _timer?.cancel();
  }
}

class _AppSettingsStore implements TechSettingsStore {
  const _AppSettingsStore();
  @override
  String userDefault(String key) => bind.mainGetUserDefaultOption(key: key);
  @override
  Future<void> setUserDefault(String key, String value) => bind.mainSetUserDefaultOption(key: key, value: value);
  @override
  bool localBool(String key) => mainGetLocalBoolOptionSync(key);
  @override
  Future<void> setLocalBool(String key, bool value) async => mainSetLocalBoolOption(key, value);
  @override
  String get no => defaultOptionNo;
}

/// TB-20's install flow through the native bridge (src/flutter_ffi.rs `dolphin-update-stage`, `-apply`, `-progress`).
class AppUpdateInstaller implements UpdateInstaller {
  const AppUpdateInstaller();

  @override
  Future<void> stage(File file, LatestRelease release) => bind.mainSetCommon(
      key: 'dolphin-update-stage',
      value: jsonEncode({'path': file.path, 'version': release.version, 'sha256': release.sha256, 'size': release.size}));

  @override
  Future<void> apply() => bind.mainSetCommon(key: 'dolphin-update-apply', value: '');

  @override
  Future<InstallProgress> progress() async =>
      InstallProgress.fromJson(await bind.mainGetCommon(key: 'dolphin-update-progress'));
}

/// The main window's first size: 1120 × 720 (min 960 × 640). Upstream remembers size and position after that
/// (restoreWindowPosition, the outgoing build stores its size).
Future<void> applyTechWindowSize() async {
  if (!isWindows) return;
  try {
    await windowManager.setMinimumSize(const Size(960, 640));
    final saved = bind.getLocalFlutterOption(k: '${windowFramePrefix}Main');
    final size = await windowManager.getSize();
    if (saved.isEmpty || size.width < 960 || size.height < 640) {
      await windowManager.setSize(const Size(1120, 720));
      if (saved.isEmpty) await windowManager.center();
    }
  } catch (_) {}
}
