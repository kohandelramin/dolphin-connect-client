import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'brand.dart';
import 'connection_view.dart';
import 'home.dart';
import 'home_view.dart';
import 'verify.dart';

/// Connections the customer ended from this window («پایان» or «رد»), for the ended screen's reason (UX-6).
final _endedByCustomer = <int>{};

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

  @override
  void initState() {
    super.initState();
    // Twice a second: re-check what the portal said about this peer, and note when the session started.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() {
        if (widget.client.authorized && !widget.client.disconnected) _sessionStart ??= DateTime.now();
        if (widget.client.disconnected) _endedAt ??= DateTime.now();
      });
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
      // After the end there is nothing to wait for: decide on what the portal pushed.
      portalDown: opt(kDolphinPortalDownOption) == 'Y',
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

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<ServerModel>(context);
    final c = widget.client;
    final peerName = c.name.isEmpty ? c.peerId : c.name;
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
          bind.cmCloseConnection(connId: c.id);
        },
      );
    }
    return DolphinSessionView(
      technician: verdict.state == TechCheck.verified && verdict.name.isNotEmpty ? verdict.name : peerName,
      elapsed: sessionElapsed(_sessionStart, DateTime.now()),
      keyboard: c.keyboard,
      clipboard: c.clipboard,
      file: c.file,
      onToggle: (name, enabled) {
        bind.cmSwitchPermission(connId: c.id, name: name, enabled: enabled);
        setState(() {
          if (name == 'keyboard') c.keyboard = enabled;
          if (name == 'clipboard') c.clipboard = enabled;
          if (name == 'file') c.file = enabled;
        });
      },
      onEnd: () {
        _endedByCustomer.add(c.id);
        bind.cmCloseConnection(connId: c.id);
      },
    );
  }
}
