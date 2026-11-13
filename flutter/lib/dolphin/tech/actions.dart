import '../panel_bridge.dart' show panelCodePattern, panelIdPattern;
import 'api.dart';
import 'cache.dart';

/// Plan 19: what the technician does to a PC from the native app. «اتصال» first opens the call on the portal (POST
/// /calls: the same checks, authorization and audit as the web's «اتصال»), then opens the remote session to the PC's
/// Dolphin Connect ID exactly as the app does today for the panel's `dolphin-connect` message
/// (technician_home.dart → common.dart `connect(context, id, password: code)`), through [SessionLauncher]. Nothing here
/// changes how a session connects (routing, codecs, transport).

/// Opens remote sessions and reads the app's own state. The app's implementation is `launcher.dart`
/// (RustdeskSessionLauncher); tests use a fake.
abstract class SessionLauncher {
  /// Opens the remote window to [rustdeskId]. [password]: the customer's one-time code (code mode, or read on the
  /// phone in click mode, ADR-0012); null in click mode, where the customer accepts or the build's fixed password
  /// applies (ADR-0015).
  Future<void> open(String rustdeskId, {String? password});

  /// This app's own Dolphin Connect ID.
  Future<String> myId();

  /// The Dolphin Connect IDs of the last sessions this app opened, newest first (the app's own history).
  Future<List<String>> recentIds({int limit = 5});
}

/// «ارائه دمو» (D1–D2): what happens after the portal authorized the demo. p19-demo implements it (reverse
/// connection); this file only defines it.
abstract class DemoStarter {
  Future<void> startDemo(DemoTarget target);
}

class DemoTarget {
  final String deviceId;
  final String rustdeskId;
  final String requestId;
  final DateTime? authorizedUntil;
  const DemoTarget({required this.deviceId, required this.rustdeskId, required this.requestId, this.authorizedUntil});
}

/// The PC an action is about: its portal id and its Dolphin Connect ID.
class PcRef {
  final String deviceId;
  final String rustdeskId;
  final String? name;
  const PcRef(this.deviceId, this.rustdeskId, [this.name]);
  factory PcRef.of(Computer c) => PcRef(c.id, c.rustdeskId, c.displayName);
}

/// What «اتصال» (or «ارائه دمو») came to.
sealed class ConnectOutcome {
  const ConnectOutcome();
}

/// The call is open and the remote window was opened (for a demo: handed to [DemoStarter]).
class Connected extends ConnectOutcome {
  final CallStart call;
  const Connected(this.call);
}

/// A code-mode call waits for the customer's one-time code (TB-21): the session is not opened yet. When the technician
/// has the code, [TechActions.openWithCode].
class WaitingForCode extends ConnectOutcome {
  final CallStart call;
  const WaitingForCode(this.call);
}

/// Another technician holds the PC's session (409 `in_session_other`). Ask, then connect again with `takeover: true`.
class HeldByOther extends ConnectOutcome {
  final String holderName;
  const HeldByOther(this.holderName);
}

/// The portal refused (not linked, inactive account, …): show [error].message.
class Refused extends ConnectOutcome {
  final ApiError error;
  const Refused(this.error);
}

/// The portal could not be reached: nothing was opened.
class PortalAway extends ConnectOutcome {
  final PortalUnreachable error;
  const PortalAway(this.error);
}

/// The launcher failed after the call was opened (the call stays open on the portal).
class LaunchFailed extends ConnectOutcome {
  final CallStart call;
  const LaunchFailed(this.call);
}

const kMsgCodeFormat = 'رمز فقط حرف انگلیسی و رقم است، ۶ تا ۱۲ نویسه. اگر صفحه‌کلید فارسی است، آن را انگلیسی کنید.';
const kMsgLaunchFailed = 'پنجره‌ی اتصال باز نشد؛ دوباره «اتصال» را بزنید.';
const kMsgBadId = 'شناسه‌ی این رایانه درست نیست.';

/// A one-time code as typed (spaces and dashes dropped), or null when it is not one (6–12 English letters or digits).
String? cleanCode(String typed) {
  final c = typed.replaceAll(RegExp(r'[\s-]'), '');
  return panelCodePattern.hasMatch(c) ? c : null;
}

/// A recent session joined with what the list knows about that PC (null when the PC is not in the list).
class RecentPc {
  final String rustdeskId;
  final Computer? computer;
  const RecentPc(this.rustdeskId, this.computer);
  String get displayName => computer?.displayName ?? rustdeskId;
}

/// The recent strip: [ids] newest first, each with its PC from [known] (live rows or the offline cache).
List<RecentPc> joinRecent(List<String> ids, Iterable<Computer> known) {
  final byId = <String, Computer>{};
  for (final c in known) {
    byId.putIfAbsent(c.rustdeskId, () => c);
  }
  final seen = <String>{};
  return [
    for (final id in ids)
      if (seen.add(id)) RecentPc(id, byId[id]),
  ];
}

class TechActions {
  final ApiClient api;
  final SessionLauncher launcher;
  final DemoStarter? demoStarter;

  /// Called after this app's ID was registered on the portal (so the session store can keep it).
  final Future<void> Function(String rustdeskId)? onIdRegistered;

  TechActions(this.api, this.launcher, {this.demoStarter, this.onIdRegistered});

  /// «اتصال»: POST /calls, then the remote window. [password]: a code the technician typed (see [SessionLauncher.open]).
  Future<ConnectOutcome> connect(PcRef pc, {bool takeover = false, String? password}) =>
      _start(pc, takeover: takeover, password: password, demo: false);

  /// «ارائه دمو»: POST /demo, then [DemoStarter]. Without a starter (p19-demo not merged) the call is authorized and
  /// [LaunchFailed] says nothing opened.
  Future<ConnectOutcome> demo(PcRef pc, {bool takeover = false}) => _start(pc, takeover: takeover, demo: true);

  Future<ConnectOutcome> _start(PcRef pc, {required bool takeover, String? password, required bool demo}) async {
    if (!panelIdPattern.hasMatch(pc.rustdeskId)) return const Refused(ApiError(400, 'invalid', kMsgBadId));
    if (password != null && cleanCode(password) == null) return const Refused(ApiError(400, 'invalid', kMsgCodeFormat));
    CallStart call;
    try {
      call = await _authorize(pc.deviceId, takeover: takeover, demo: demo);
    } on ApiError catch (e) {
      if (e.status == 409 && e.code == 'in_session_other') {
        final holder = e.extra['holderName'];
        return HeldByOther(holder is String ? holder : '');
      }
      if (e.status == 409 && e.code == 'technician_id_missing' && await _registerMyId()) {
        try {
          call = await _authorize(pc.deviceId, takeover: takeover, demo: demo);
        } on ApiError catch (e2) {
          if (e2.status == 409 && e2.code == 'in_session_other') {
            final holder = e2.extra['holderName'];
            return HeldByOther(holder is String ? holder : '');
          }
          return Refused(e2);
        } on PortalUnreachable catch (u) {
          return PortalAway(u);
        }
      } else {
        return Refused(e);
      }
    } on PortalUnreachable catch (e) {
      return PortalAway(e);
    }
    if (demo) {
      final starter = demoStarter;
      if (starter == null) return LaunchFailed(call);
      try {
        await starter.startDemo(DemoTarget(
            deviceId: pc.deviceId, rustdeskId: pc.rustdeskId, requestId: call.requestId, authorizedUntil: call.authorizedUntil));
        return Connected(call);
      } catch (_) {
        return LaunchFailed(call);
      }
    }
    final code = password == null ? null : cleanCode(password);
    if (call.waiting && code == null) return WaitingForCode(call);
    try {
      await launcher.open(pc.rustdeskId, password: code);
      return Connected(call);
    } catch (_) {
      return LaunchFailed(call);
    }
  }

  Future<CallStart> _authorize(String deviceId, {required bool takeover, required bool demo}) =>
      demo ? api.startDemo(deviceId, takeover: takeover) : api.startCall(deviceId, takeover: takeover);

  /// A code-mode call that was waiting: the technician has the customer's code. Opens the remote window only.
  Future<ConnectOutcome> openWithCode(PcRef pc, CallStart call, String typed) async {
    final code = cleanCode(typed);
    if (code == null) return const Refused(ApiError(400, 'invalid', kMsgCodeFormat));
    try {
      await launcher.open(pc.rustdeskId, password: code);
      return Connected(call);
    } catch (_) {
      return LaunchFailed(call);
    }
  }

  /// TD-2, portal away: opens the remote window without a new call. Whether the server lets it through depends on an
  /// authorization the portal gave earlier (the engine decides, not this app); nothing is weakened here.
  Future<bool> connectOffline(String rustdeskId, {String? password}) async {
    if (!panelIdPattern.hasMatch(rustdeskId)) return false;
    try {
      await launcher.open(rustdeskId, password: password == null ? null : cleanCode(password));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Registers this app's ID with the portal (WF-7), as the panel did on hello. True when it was registered.
  Future<bool> _registerMyId() async {
    try {
      final id = await launcher.myId();
      if (!panelIdPattern.hasMatch(id)) return false;
      await api.setMyRustdeskId(id);
      await onIdRegistered?.call(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// After sign-in: registers this app's ID when the portal has another (or none). Returns the portal's refusal in
  /// Persian (e.g. a live session from the old app), or null when nothing was needed or it worked.
  Future<String?> ensureMyId(StaffInfo staff) async {
    try {
      final id = await launcher.myId();
      if (!panelIdPattern.hasMatch(id) || staff.rustdeskId == id) return null;
      await api.setMyRustdeskId(id);
      await onIdRegistered?.call(id);
      return null;
    } on ApiError catch (e) {
      return e.message;
    } on PortalUnreachable catch (e) {
      return e.message;
    } catch (_) {
      return null;
    }
  }

  // -- the open call (RO-8: end with reason and note)

  /// «پایان تماس» with the tapped reason and an optional note.
  Future<void> endCall(String requestId, {String? reasonId, String? note}) =>
      api.endCall(requestId, reasonId: reasonId, note: note);
  Future<void> setReason(String requestId, String? reasonId) => api.setReason(requestId, reasonId);
  Future<void> addNote(String requestId, String text) => api.addNote(requestId, text);
  Future<void> sendMessage(String requestId, String text) => api.sendMessage(requestId, text);

  /// Audits a pasted ready-made text (never its body).
  Future<void> snippetUsed(String snippetId, String rustdeskId) => api.snippetUsed(snippetId, rustdeskId: rustdeskId);

  // -- recent

  /// The recent strip: the app's last sessions, joined with the PCs the list knows. Empty when the app cannot say.
  Future<List<RecentPc>> recent(Iterable<Computer> known, {int limit = 5}) async {
    try {
      final ids = await launcher.recentIds(limit: limit);
      return joinRecent(ids.where(panelIdPattern.hasMatch).take(limit).toList(), known);
    } catch (_) {
      return const [];
    }
  }

  /// The recent strip from the offline cache.
  Future<List<RecentPc>> recentOffline(OfflineSnapshot? snap, {int limit = 5}) =>
      recent((snap?.items ?? const <CachedComputer>[]).map((c) => c.toComputer()), limit: limit);
}
