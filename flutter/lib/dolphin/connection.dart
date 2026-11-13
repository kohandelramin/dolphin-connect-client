import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../consts.dart';
import '../common.dart';
import '../models/chat_model.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'brand.dart';
import 'connection_view.dart';
import 'home.dart';
import 'home_view.dart';
import 'reconnect.dart';
import 'session_controls.dart';
import 'tech_card.dart';
import 'verify.dart';

/// Connections the customer ended from this window («پایان» or «رد»), for the ended screen's reason (UX-6).
final _endedByCustomer = <int>{};

/// D23: when each technician (peer ID) was last seen in a live session in this window. Forgotten when the customer ends
/// the session, so only a drop, not the customer's «پایان», makes the next session «دوباره وصل شد».
final _lastLive = <String, DateTime>{};

/// DD-36: the window size this window last asked for, and the size the window reported right after the small one was
/// set; one window serves every tab.
DolphinWindowMode? _windowMode;
Size? _compactSeen;
bool _fitting = false;
bool _fitAgain = false;

/// Customer build's connection window for one incoming client. Unlike upstream, accepting does not
/// minimize the window: the customer keeps seeing who is connected and the End button (SECURITY control 2).
class DolphinConnection extends StatefulWidget {
  final Client client;
  const DolphinConnection({super.key, required this.client});

  @override
  State<DolphinConnection> createState() => _DolphinConnectionState();
}

class _DolphinConnectionState extends State<DolphinConnection> {
  Timer? _timer;
  final _shownAt = DateTime.now();
  DateTime? _sessionStart;
  DateTime? _endedAt;
  bool _closing = false;
  // Fixed at the first build after the end (see latchReason); the screen must not change its mind.
  bool? _byCustomer;
  DolphinEndReason? _reason;
  late final bool _resumed;
  // DD-37: when the technician's block of the customer's input was first seen.
  DateTime? _inputOffSince;

  @override
  void initState() {
    super.initState();
    // Remote control only: a file-transfer tab opened beside a live session is not a comeback.
    _resumed = widget.client.type_() == ClientType.remote && dolphinResumed(_lastLive[widget.client.peerId], DateTime.now());
    // Twice a second: re-check what the portal said about this peer, and note when the session started.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() {
        if (widget.client.authorized && !widget.client.disconnected) {
          _sessionStart ??= DateTime.now();
          if (widget.client.type_() == ClientType.remote && !_endedByCustomer.contains(widget.client.id)) {
            _lastLive[widget.client.peerId] = DateTime.now();
          }
        }
        if (widget.client.disconnected) _endedAt ??= DateTime.now();
        _inputOffSince = inputOffSince(_inputOffSince, widget.client.dolphinInputBlocked, DateTime.now());
      });
      _keepCompact();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  TechVerdict _verdict({bool decided = false}) {
    String opt(String key) => bind.mainGetOptionSync(key: key);
    return verifyTechnician(
      peerId: widget.client.peerId,
      techId: opt(kDolphinTechIdOption),
      techName: opt(kDolphinTechNameOption),
      until: int.tryParse(opt(kDolphinTechUntilOption)) ?? 0,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      portalDown: opt(kDolphinPortalDownOption) == 'Y',
      // After the end there is nothing to wait for: decide on what the portal pushed.
      waitedMs: decided ? kDolphinVerifyWaitMs : DateTime.now().difference(_shownAt).inMilliseconds,
    );
  }

  /// As upstream's tab close for an ended connection (server_page.dart handleClose).
  Future<void> _closeEnded() async {
    if (_closing) return;
    _closing = true;
    _endedByCustomer.remove(widget.client.id);
    try {
      await bind.cmRemoveDisconnectedConnection(connId: widget.client.id);
      if (await bind.cmGetClientsLength() == 0) await windowManager.close();
    } finally {
      // A failure must not leave «بستن» and the automatic close dead.
      _closing = false;
    }
  }

  void _permissions(bool keyboard, bool clipboard, bool file) {
    final c = widget.client;
    bind.cmSwitchPermission(connId: c.id, name: 'keyboard', enabled: keyboard);
    bind.cmSwitchPermission(connId: c.id, name: 'clipboard', enabled: clipboard);
    bind.cmSwitchPermission(connId: c.id, name: 'file', enabled: file);
    c.keyboard = keyboard;
    c.clipboard = clipboard;
    c.file = file;
  }

  /// DD-36: the small window in the corner during a session, the full one for the prompt and the ended screen. Only the
  /// tab on screen decides. The chat side panel (upstream) still sets its own size when it opens or closes.
  void _fitWindow(ServerModel model) {
    final c = widget.client;
    final wanted = windowModeFor(authorized: c.authorized, disconnected: c.disconnected);
    final tabs = model.tabController.state.value;
    final selected =
        tabs.selected >= 0 && tabs.selected < tabs.tabs.length && tabs.tabs[tabs.selected].key == c.id.toString();
    if (!windowNeedsResize(selected: selected, wanted: wanted, current: _windowMode)) return;
    _windowMode = wanted;
    _compactSeen = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _applySize());
  }

  /// Sets the size [_windowMode] asks for; a change that comes while a resize runs is applied right after it.
  Future<void> _applySize() async {
    if (_fitting) {
      _fitAgain = true;
      return;
    }
    _fitting = true;
    try {
      do {
        _fitAgain = false;
        if (_windowMode == DolphinWindowMode.compact) {
          await windowManager.setSizeAlignment(kDolphinSessionWindowSize, Alignment.topRight);
          _compactSeen = await windowManager.getSize();
        } else {
          await windowManager.setSizeAlignment(kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
        }
      } while (_fitAgain);
    } finally {
      _fitting = false;
    }
  }

  /// Upstream sets its own size when the window is shown at start or brought back, and when the chat closes; a live
  /// session takes the small one back then ([windowNeedsRefit]). The open chat is left alone.
  Future<void> _keepCompact() async {
    if (_fitting || _windowMode != DolphinWindowMode.compact || _compactSeen == null) return;
    if (windowModeFor(authorized: widget.client.authorized, disconnected: widget.client.disconnected) !=
        DolphinWindowMode.compact) {
      return;
    }
    final current = await windowManager.getSize();
    if (windowNeedsRefit(seen: _compactSeen, current: current)) await _applySize();
  }

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<ServerModel>(context);
    final c = widget.client;
    final peerName = c.name.isEmpty ? c.peerId : c.name;
    _fitWindow(model);
    if (c.disconnected) {
      if (!c.authorized) {
        // Refused or cut before Accept: nothing to report, so the tab goes as it did before (UX-6).
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeEnded());
        return const SizedBox.shrink();
      }
      final endedAt = _endedAt;
      _byCustomer ??= _endedByCustomer.contains(c.id);
      _reason = latchReason(
          _reason,
          endReason(
              byCustomer: _byCustomer!,
              verdictNow: _verdict(decided: true).state,
              sinceEndMs: endedAt == null ? 0 : DateTime.now().difference(endedAt).inMilliseconds));
      return DolphinEndedView(
        reason: _reason,
        onClose: _closeEnded,
      );
    }
    final verdict = _verdict();
    if (!c.authorized) {
      final showElevate = bind.cmCanElevate() &&
          model.showElevation &&
          c.type_() == ClientType.remote &&
          bind.mainGetBuildinOption(key: kOptionHideElevateButtonInAcceptWindow) != 'Y';
      return DolphinAcceptView(
        verdict: verdict,
        peerName: peerName,
        showElevate: showElevate,
        phone: supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone),
        // Plan 14 (B5): pushed only to the PC that technician may connect to (app/src/lib/engine/policy.ts).
        photo: verdict.state == TechCheck.verified ? techPhoto(bind.mainGetOptionSync(key: kDolphinTechPhotoOption)) : null,
        onAccept: (keyboard, clipboard, file) {
          // The button can be up to 500 ms stale: ask again at the moment of the press.
          if (!acceptAllowed(_verdict())) return;
          _sessionStart = DateTime.now();
          _permissions(keyboard, clipboard, file);
          model.sendLoginResponse(c, true);
        },
        onAcceptElevate: (keyboard, clipboard, file) {
          if (!acceptAllowed(_verdict())) return;
          _sessionStart = DateTime.now();
          _permissions(keyboard, clipboard, file);
          model.sendLoginResponse(c, true);
          model.setShowElevation(false);
          bind.cmElevatePortable(connId: c.id);
        },
        onDeny: () {
          _endedByCustomer.add(c.id);
          _lastLive.remove(c.peerId);
          bind.cmCloseConnection(connId: c.id);
        },
      );
    }
    final technician = verdict.state == TechCheck.verified && verdict.name.isNotEmpty ? verdict.name : peerName;
    final inputOffAt = _inputOffSince;
    return DolphinSessionView(
      technician: technician,
      elapsed: sessionElapsed(_sessionStart, DateTime.now()),
      keyboard: c.keyboard,
      clipboard: c.clipboard,
      file: c.file,
      resumed: _resumed,
      // DD-37: at once, from the connection's own word (src/server/connection.rs handle_input).
      inputOff: c.dolphinInputBlocked ? inputOffDetail(technician, inputOffAt ?? DateTime.now(), DateTime.now()) : null,
      // DD-46: only a remote-control session has a picture and input to stop.
      paused: c.dolphinPaused,
      onPause: c.type_() == ClientType.remote
          ? (paused) {
              bind.cmSwitchPermission(connId: c.id, name: kDolphinPauseSwitch, enabled: paused);
              setState(() {
                c.dolphinPaused = paused;
                // Pausing gives the customer their input back (the connection lifts the block).
                if (paused) c.dolphinInputBlocked = false;
              });
            }
          : null,
      onToggle: (name, enabled) {
        bind.cmSwitchPermission(connId: c.id, name: name, enabled: enabled);
        setState(() {
          if (name == 'keyboard') c.keyboard = enabled;
          // DD-37: taking keyboard and mouse away lifts the technician's block (src/server/connection.rs).
          if (name == 'keyboard' && !enabled) c.dolphinInputBlocked = false;
          if (name == 'clipboard') c.clipboard = enabled;
          if (name == 'file') c.file = enabled;
        });
      },
      onEnd: () {
        _endedByCustomer.add(c.id);
        _lastLive.remove(c.peerId);
        bind.cmCloseConnection(connId: c.id);
      },
      // DD-29: the customer opens and closes the chat beside the session (upstream's CM side page).
      onChat: c.type_() == ClientType.remote
          ? () => gFFI.chatModel.toggleCMChatPage(MessageKey(c.peerId, c.id))
          : null,
    );
  }
}
