import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../consts.dart';
import '../common.dart';
import '../models/chat_model.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'access_profile.dart';
import 'brand.dart';
import 'connection_view.dart';
import 'demo.dart';
import 'home.dart';
import 'home_view.dart';
import 'reconnect.dart';
import 'safe_mode.dart';
import 'session_controls.dart';
import 'session_frame.dart';
import 'switches.dart';
import 'tech_card.dart';
import 'theme.dart';
import 'theme_option.dart';
import 'verify.dart';

/// Connections the customer ended from this window («پایان» or «رد»), for the ended screen's reason (UX-6).
final _endedByCustomer = <int>{};

/// D23: when each technician (peer ID) was last seen in a live session in this window. Forgotten when the customer ends
/// the session, so only a drop, not the customer's «پایان», makes the next session «دوباره وصل شد».
final _lastLive = <String, DateTime>{};

/// Plan 19 (demo): connections whose «ارائه دمو» prompt was shown. The customer's PC ends such a connection after the
/// answer (the demo window takes over, or the customer said «نه»), so its tab goes without the ended screen.
final _demoAsked = <int>{};

/// DD-36: the window size this window last asked for, and the size the window reported right after the small one was
/// set; one window serves every tab.
DolphinWindowMode? _windowMode;
Size? _compactSeen;
bool _fitting = false;
bool _fitAgain = false;

/// C3: «کادر رنگی دور صفحه», the customer's choice (a local option), and the last command sent to the Rust side, so it
/// is sent only when it changes. One frame for the whole window: it shows while any technician is connected.
bool? _frameEnabled;
String? _frameSent;

bool get _frameOn => _frameEnabled ??= frameOn(bind.mainGetLocalOption(key: kDolphinFrameLocal));

void _syncFrame(ServerModel model) {
  final live = model.clients.any((c) => c.authorized && !c.disconnected);
  final cmd = frameCommand(show: frameWanted(enabled: _frameOn, liveSession: live), color: DolphinColors.frame);
  if (cmd == _frameSent) return;
  _frameSent = cmd;
  bind.mainSetCommon(key: kDolphinFrameCommon, value: cmd);
}

/// C2: the technician cannot press anything in this window from his side. Upstream already blocks his pointer when it
/// enters the window (server_page.dart `buildRemoteBlock`, because the portal pushes `allow-remote-cm-modification`
/// "N"); this is upstream's second check (`checkClickTime`) for a press made while the pointer was already inside: the
/// connection says when the technician last clicked, and a press within [kDolphinRemoteClickMs] of it is ignored.
Future<void> _localOnly(int connId, VoidCallback action) async {
  if (bind.mainGetLocalOption(key: kOptionAllowRemoteCmModification) == 'Y') {
    action();
    return;
  }
  final pressed = DateTime.now().millisecondsSinceEpoch;
  await bind.cmCheckClickTime(connId: connId);
  Timer(const Duration(milliseconds: kDolphinRemoteClickMs), () async {
    final remote = (await bind.cmGetClickTime()).toInt();
    if (clickIsLocal(pressedMs: pressed, remoteClickMs: remote)) action();
  });
}

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
  // DD-11: when the restart notice was first seen; null while there is none.
  DateTime? _restartSeenAt;
  // Plan 19 (demo): when the prompt was first seen; null while there is none.
  DateTime? _demoSeenAt;

  @override
  void initState() {
    super.initState();
    // Plan 19: the theme the main window last applied (this window has no option sync of its own).
    themeFromMainWindow();
    applyCustomerThemeChoice(); // C5: the customer's own light or dark
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
        _noteRestart();
        _noteDemo();
      });
      _keepCompact();
      _syncFrame(gFFI.serverModel);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// DD-11: the notice starts its count when first seen and brings the window forward, so the customer reads it.
  void _noteRestart() {
    if (restartKindFrom(widget.client.dolphinRestart) == null) {
      _restartSeenAt = null;
      return;
    }
    if (_restartSeenAt != null) return;
    _restartSeenAt = DateTime.now();
    windowManager.show();
    windowManager.focus();
  }

  /// Plan 19 (demo): the prompt brings the window forward when it first shows, so the customer sees it.
  void _noteDemo() {
    if (!widget.client.dolphinDemoAsk) {
      _demoSeenAt = null;
      return;
    }
    if (_demoSeenAt != null) return;
    _demoSeenAt = DateTime.now();
    _demoAsked.add(widget.client.id);
    windowManager.show();
    windowManager.focus();
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

  /// C2: what the customer allowed in the prompt, sound included (DD-31: off unless they turned it on).
  void _permissions(DolphinGrant g) {
    final c = widget.client;
    bind.cmSwitchPermission(connId: c.id, name: 'keyboard', enabled: g.keyboard);
    bind.cmSwitchPermission(connId: c.id, name: 'clipboard', enabled: g.clipboard);
    bind.cmSwitchPermission(connId: c.id, name: 'file', enabled: g.file);
    bind.cmSwitchPermission(connId: c.id, name: 'audio', enabled: g.audio);
    c.keyboard = g.keyboard;
    c.clipboard = g.clipboard;
    c.file = g.file;
    c.audio = g.audio;
  }

  /// DD-31: whether the organization offers the PC's sound (`remote-sound` not hidden).
  bool get _soundOffered =>
      DolphinSwitches.parse(bind.mainGetOptionSync(key: kDolphinSwitchesOption)).shown(DolphinSwitch.remoteSound);

  void _local(VoidCallback action) => _localOnly(widget.client.id, action);

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
          // C3: the session window sits in the bottom corner, above the taskbar (design C3); the prompt stays top right.
          await windowManager.setSizeAlignment(kDolphinSessionWindowSize, Alignment.bottomRight);
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
      // Plan 19 (demo): ended by this PC after the customer's answer; nothing to report.
      if (_demoAsked.remove(c.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeEnded());
        return const SizedBox.shrink();
      }
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
        soundOffered: _soundOffered,
        onAccept: (grant) => _local(() {
          // The button can be up to 500 ms stale: ask again at the moment of the press.
          if (!acceptAllowed(_verdict())) return;
          _sessionStart = DateTime.now();
          _permissions(grant);
          model.sendLoginResponse(c, true);
        }),
        onAcceptElevate: (grant) => _local(() {
          if (!acceptAllowed(_verdict())) return;
          _sessionStart = DateTime.now();
          _permissions(grant);
          model.sendLoginResponse(c, true);
          model.setShowElevation(false);
          bind.cmElevatePortable(connId: c.id);
        }),
        onDeny: () => _local(() {
          _endedByCustomer.add(c.id);
          _lastLive.remove(c.peerId);
          bind.cmCloseConnection(connId: c.id);
        }),
      );
    }
    // DD-11: the technician asked for a Safe Mode or normal restart; «لغو» tells him (src/server/connection.rs).
    final restart = restartKindFrom(c.dolphinRestart);
    if (restart != null) {
      return DolphinRestartNoticeView(
        kind: restart,
        secondsLeft: restartSecondsLeft(_restartSeenAt ?? DateTime.now(), DateTime.now()),
        onCancel: () => _local(() {
          bind.cmSwitchPermission(connId: c.id, name: kDolphinRestartCancel, enabled: false);
          setState(() {
            c.dolphinRestart = '';
            _restartSeenAt = null;
          });
        }),
      );
    }
    final technician = verdict.state == TechCheck.verified && verdict.name.isNotEmpty ? verdict.name : peerName;
    // Plan 19 (demo): the technician asks to show his screen; nothing is shown before «دیدن» (src/server/connection.rs).
    if (c.dolphinDemoAsk) {
      void answer(bool see) {
        bind.cmSwitchPermission(connId: c.id, name: kDolphinDemoAnswer, enabled: see);
        setState(() => c.dolphinDemoAsk = false);
      }

      return DolphinDemoAskView(
        technician: technician,
        canSee: acceptAllowed(verdict),
        secondsLeft: demoSecondsLeft(_demoSeenAt ?? DateTime.now(), DateTime.now()),
        phone: supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone),
        // As the accept prompt (D5): asked again at the moment of the press. The technician is connected while this
        // asks, so a press from his side is ignored (Plan 19 C2, [_localOnly]).
        onSee: () => _local(() {
          if (acceptAllowed(_verdict())) answer(true);
        }),
        onNo: () => _local(() => answer(false)),
      );
    }
    final inputOffAt = _inputOffSince;
    return DolphinSessionView(
      technician: technician,
      elapsed: sessionElapsed(_sessionStart, DateTime.now()),
      keyboard: c.keyboard,
      clipboard: c.clipboard,
      file: c.file,
      audio: c.audio,
      soundOffered: _soundOffered,
      resumed: _resumed,
      // DD-37: at once, from the connection's own word (src/server/connection.rs handle_input).
      inputOff: c.dolphinInputBlocked ? inputOffDetail(technician, inputOffAt ?? DateTime.now(), DateTime.now()) : null,
      // DD-46: only a remote-control session has a picture and input to stop.
      paused: c.dolphinPaused,
      onPause: c.type_() == ClientType.remote
          ? (paused) => _local(() {
                bind.cmSwitchPermission(connId: c.id, name: kDolphinPauseSwitch, enabled: paused);
                setState(() {
                  c.dolphinPaused = paused;
                  // Pausing gives the customer their input back (the connection lifts the block).
                  if (paused) c.dolphinInputBlocked = false;
                });
              })
          : null,
      onToggle: (name, enabled) => _local(() {
        bind.cmSwitchPermission(connId: c.id, name: name, enabled: enabled);
        setState(() {
          if (name == 'keyboard') c.keyboard = enabled;
          // DD-37: taking keyboard and mouse away lifts the technician's block (src/server/connection.rs).
          if (name == 'keyboard' && !enabled) c.dolphinInputBlocked = false;
          if (name == 'clipboard') c.clipboard = enabled;
          if (name == 'file') c.file = enabled;
          if (name == 'audio') c.audio = enabled;
        });
      }),
      // C3: the customer's own choice, kept for the next session and shown in «تنظیمات» (C5).
      frame: _frameOn,
      onFrame: (on) => _local(() {
        _frameEnabled = on;
        bind.mainSetLocalOption(key: kDolphinFrameLocal, value: frameValue(on));
        setState(() {});
        _syncFrame(model);
      }),
      onEnd: () => _local(() {
        _endedByCustomer.add(c.id);
        _lastLive.remove(c.peerId);
        bind.cmCloseConnection(connId: c.id);
      }),
      // DD-29: the customer opens and closes the chat beside the session (upstream's CM side page).
      onChat: c.type_() == ClientType.remote
          ? () => gFFI.chatModel.toggleCMChatPage(MessageKey(c.peerId, c.id))
          : null,
    );
  }
}
