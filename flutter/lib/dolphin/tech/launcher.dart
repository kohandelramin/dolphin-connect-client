import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import 'actions.dart';
import 'state.dart' show Prefs;

/// Plan 19: the app side of [SessionLauncher] and [Prefs] (the only tech/ file that touches the app's native bridge,
/// so everything else stays unit-testable). Not covered by unit tests: it needs the running app.

/// Opens remote sessions exactly as the technician app does today for the panel's `dolphin-connect` message
/// (as the old technician_home.dart did: `connect(context, id, password: code)`), so connections, routing and codecs are unchanged.
class RustdeskSessionLauncher implements SessionLauncher {
  /// The context `connect` is given (on desktop it is only used off the main window); the navigator's by default.
  final BuildContext? Function() context;
  RustdeskSessionLauncher({BuildContext? Function()? context}) : context = context ?? (() => globalKey.currentContext);

  @override
  Future<void> open(String rustdeskId, {String? password}) async {
    final ctx = context();
    if (ctx == null) throw StateError('no context');
    await connect(ctx, rustdeskId, password: password);
  }

  @override
  Future<String> myId() => bind.mainGetMyId();

  /// The app's own recent sessions: upstream's recent peers (newest first), loaded through its event. Unverified in a
  /// running build: the event fills `gFFI.recentPeersModel` asynchronously, so this waits up to 2 s for it.
  @override
  Future<List<String>> recentIds({int limit = 5}) async {
    final model = gFFI.recentPeersModel;
    final done = Completer<void>();
    void onChange() {
      if (!done.isCompleted) done.complete();
    }

    model.addListener(onChange);
    try {
      await bind.mainLoadRecentPeers();
      await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    } finally {
      model.removeListener(onChange);
    }
    return model.peers.map((p) => p.id).take(limit).toList();
  }
}

/// [Prefs] in the app's local options (the same store as the side pane's `kDolphinSideOption`): small UI choices
/// such as tiles or list. Never used for the token or anything secret.
class LocalOptionPrefs implements Prefs {
  const LocalOptionPrefs();
  @override
  String? get(String key) {
    final v = bind.mainGetLocalOption(key: key);
    return v.isEmpty ? null : v;
  }

  @override
  Future<void> set(String key, String? value) => bind.mainSetLocalOption(key: key, value: value ?? '');
}
