import 'dart:io';

import 'package:flutter/material.dart';

/// Plan 19: what the native technician screens need from the running app, behind interfaces so every screen is
/// tested with fakes. The app's implementation is app_platform.dart (the native bridge, window manager and the
/// session windows); nothing in these files changes how a session connects.

/// One remote session window's peer, as the main window sees it (TD-9).
class OpenSession {
  final String rustdeskId;

  /// When the main window first saw it open.
  final DateTime since;
  const OpenSession(this.rustdeskId, this.since);
}

/// The open sessions for the bottom bar. The app polls its session windows; tests set [open] directly.
class TechSessions extends ChangeNotifier {
  List<OpenSession> _open = const [];
  List<OpenSession> get open => _open;

  /// Replaces the list (keeping each session's first-seen time) and notifies when it changed.
  void update(List<String> ids, DateTime now) {
    final known = {for (final s in _open) s.rustdeskId: s};
    final next = [for (final id in ids.toSet()) known[id] ?? OpenSession(id, now)];
    final same = next.length == _open.length && next.every((s) => known.containsKey(s.rustdeskId));
    _open = next;
    if (!same) notifyListeners();
  }

  /// Ids that were open in [before] and are gone now.
  static List<String> ended(List<OpenSession> before, List<OpenSession> now) {
    final still = now.map((s) => s.rustdeskId).toSet();
    return [for (final s in before) if (!still.contains(s.rustdeskId)) s.rustdeskId];
  }
}

/// The technician's RO-10 display preferences and the window behaviour, stored in upstream's own options so the
/// session windows read them exactly as upstream's settings page writes them.
abstract class TechSettingsStore {
  /// upstream `mainGetUserDefaultOption` (view_style, scroll_style, zoom-cursor, …); '' when unset.
  String userDefault(String key);
  Future<void> setUserDefault(String key, String value);

  /// upstream `mainGetLocalBoolOptionSync` / `mainSetLocalBoolOption` (open new connections in tabs).
  bool localBool(String key);
  Future<void> setLocalBool(String key, bool value);

  /// upstream's "no" for a user-default switch ('N' in a custom client, '' otherwise: `defaultOptionNo`).
  String get no;
}

class MemorySettingsStore implements TechSettingsStore {
  final Map<String, String> user;
  final Map<String, bool> local;
  MemorySettingsStore({Map<String, String>? user, Map<String, bool>? local})
      : user = user ?? {},
        local = local ?? {};
  @override
  String userDefault(String key) => user[key] ?? '';
  @override
  Future<void> setUserDefault(String key, String value) async => user[key] = value;
  @override
  bool localBool(String key) => local[key] ?? false;
  @override
  Future<void> setLocalBool(String key, bool value) async => local[key] = value;
  @override
  String get no => 'N';
}

abstract class TechPlatform {
  /// This app's Dolphin Connect ID ('' while unknown).
  Future<String> myId();

  /// DD-53: the technician's theme choice (upstream's `theme` option, so the session windows follow it).
  ThemeMode get themeMode;
  Future<void> setThemeMode(ThemeMode mode);

  Future<void> openUrl(String url);
  Future<void> copy(String text);

  /// The main window is focused and not minimized.
  Future<bool> appInFront();

  /// A Windows notice with its sound (UN-16's `--dolphin-notify`): one plain line.
  Future<void> systemToast(String text);

  /// Where «فرستاده‌ی مشتری» downloads go.
  Future<Directory> downloadsDir();
  Future<void> openFolder(String path);

  /// Brings the session window with this peer to the front (TD-9). False when no window has it.
  Future<bool> focusSession(String rustdeskId);

  TechSettingsStore get settings;

  /// The engine server (hbbs) answers: «سرور دلفین: وصل». Null while unknown.
  ValueNotifier<bool?> get serverOnline;

  TechSessions get sessions;

  /// The installed version («نسخه‌ی ۲.۱.۰»).
  String get version;
}
