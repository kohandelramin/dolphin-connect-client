import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../consts.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'connection_view.dart';
import 'verify.dart';

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
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Twice a second: re-check what the portal said about this peer, and count the session's time.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      setState(() {
        if (widget.client.authorized && !widget.client.disconnected && t.tick.isEven) {
          _elapsed += const Duration(seconds: 1);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  TechVerdict _verdict() {
    String opt(String key) => bind.mainGetOptionSync(key: key);
    return verifyTechnician(
      peerId: widget.client.peerId,
      techId: opt(kDolphinTechIdOption),
      techName: opt(kDolphinTechNameOption),
      until: int.tryParse(opt(kDolphinTechUntilOption)) ?? 0,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      waitedMs: DateTime.now().difference(_shownAt).inMilliseconds,
    );
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
      return DolphinEndedView(onClose: () => bind.cmCloseConnection(connId: c.id));
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
        onAccept: (keyboard, clipboard, file) {
          _permissions(keyboard, clipboard, file);
          model.sendLoginResponse(c, true);
        },
        onAcceptElevate: (keyboard, clipboard, file) {
          _permissions(keyboard, clipboard, file);
          model.sendLoginResponse(c, true);
          model.setShowElevation(false);
          bind.cmElevatePortable(connId: c.id);
        },
        onDeny: () => bind.cmCloseConnection(connId: c.id),
      );
    }
    return DolphinSessionView(
      technician: verdict.state == TechCheck.verified && verdict.name.isNotEmpty ? verdict.name : peerName,
      elapsed: _elapsed,
      fileEnabled: c.file,
      onFile: (enabled) {
        bind.cmSwitchPermission(connId: c.id, name: 'file', enabled: enabled);
        setState(() => c.file = enabled);
      },
      onEnd: () => bind.cmCloseConnection(connId: c.id),
    );
  }
}
