import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart' hide Dialog;
import '../models/model.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import '../models/state_model.dart';
import 'demo.dart';
import 'verify.dart';

/// Plan 19 (D1–D2): the wiring of demo.dart. The technician's dashboard ([startDemo], [showDolphinDemoConfirm]), his
/// session window (hooks in side_pane.dart and models/model.dart), the red bar in his connection-manager window (hook in
/// desktop/pages/server_page.dart), the customer's demo window (hooks in desktop/pages/remote_page.dart and
/// models/model.dart); the customer's prompt is in connection.dart.

// ---- the technician: dashboard ----

/// What the dashboard calls once the portal authorized the demo (`POST /api/app/v1/demo`, p19-techdata's
/// `DemoStarter`). Opens an ordinary session to the PC, marked as the demo: when it is in, the session asks the
/// customer's PC and the customer presses «دیدن» first. Nothing here talks to the portal.
Future<void> startDemo(String peerId, {bool allScreens = false, BuildContext? context}) async {
  final id = peerId.replaceAll(' ', '');
  if (id.isEmpty) return;
  await bind.mainSetCommon(key: kDolphinDemoIntentKey, value: demoIntentValue(id, allScreens));
  final ctx = context ?? globalKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  await connect(ctx, id);
}

/// The D1 confirmation: whether all his screens (true / false), or null when he cancelled.
Future<bool?> showDolphinDemoConfirm(BuildContext context, String peerName) => showDialog<bool>(
      context: context,
      builder: (context) {
        var all = false;
        return StatefulBuilder(
          builder: (context, setState) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DolphinDemoConfirmView(
                peerName: peerName,
                allScreens: all,
                onAllScreens: (v) => setState(() => all = v),
                onStart: () => Navigator.of(context).pop(all),
                onCancel: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
    );

// ---- the technician: the session window ----

class _Demo {
  /// "all" / "primary" when this window is the dashboard's demo; null for an ordinary session.
  final String? screens;
  bool asked = false;

  /// The PC's last word came: the connection's own end says nothing more.
  bool finished = false;
  Timer? reply;
  _Demo(this.screens);
}

final _demos = Expando<_Demo>('dolphin-demo');

String _tag(FFI ffi) => '${ffi.sessionId}-dolphin-demo';

/// When the session window opens: whether the dashboard asked for a demo to this PC (taken once).
void dolphinDemoWindowOpened(FFI ffi) {
  if (!bind.isOutgoingOnly() || _demos[ffi] != null) return;
  final screens = bind.sessionGetCommonSync(sessionId: ffi.sessionId, key: kDolphinDemoIntentKey, param: '') ?? '';
  _demos[ffi] = _Demo(screens.isEmpty ? null : screens);
}

/// On the session's peer info: ask the customer's PC, once, or say why a demo cannot be shown on it.
void dolphinDemoOnPeerInfo(FFI? ffi) {
  if (ffi == null) return;
  final d = _demos[ffi];
  final screens = d?.screens;
  if (d == null || screens == null || d.asked) return;
  d.asked = true;
  switch (demoCapability(ffi.ffiModel.pi.platformAdditions[kDolphinDemoAddition])) {
    case DemoCapability.x86:
      _finish(ffi, kDemoUnsupported);
      return;
    case DemoCapability.old:
      _finish(ffi, kDemoOldApp);
      return;
    case DemoCapability.yes:
      break;
  }
  bind.sessionSetCommon(sessionId: ffi.sessionId, key: kDolphinDemoKey, value: screens);
  _showWait(ffi, kDemoAsking);
  d.reply = Timer(kDolphinDemoReplyWait, () => _finish(ffi, kDemoNoReply));
}

void _showWait(FFI ffi, String text) {
  if (ffi.closed) return;
  ffi.dialogManager.dismissByTag(_tag(ffi));
  ffi.dialogManager.show(
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: DolphinDemoWaitView(text: text, onCancel: () => _finish(ffi, null)),
    ),
    tag: _tag(ffi),
  );
}

/// The end of the demo request in this window: the wait is given up in this app (so it stops being reachable) and
/// [text] is shown with «بستن», which closes the session window. Null: closed at once.
void _finish(FFI ffi, String? text) {
  final d = _demos[ffi];
  d?.reply?.cancel();
  d?.finished = true;
  bind.sessionSetCommon(sessionId: ffi.sessionId, key: kDolphinDemoCancelKey, value: '');
  if (ffi.closed) return;
  ffi.dialogManager.dismissByTag(_tag(ffi));
  if (text == null) {
    closeConnection(id: ffi.id);
    return;
  }
  ffi.dialogManager.show(
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: DolphinDemoAnswerView(text: text, onClose: () => closeConnection(id: ffi.id)),
    ),
    tag: _tag(ffi),
  );
}

/// The PC's answers (`MessageBox` of type [kDolphinDemoKey]), and the connection's end after its last word. True:
/// taken, upstream does nothing more with it (no error box, no quiet retry).
bool dolphinDemoMsgBox(FFI? ffi, dynamic type, dynamic title, dynamic text) {
  if (ffi == null) return false;
  final d = _demos[ffi];
  final answer = demoAnswerFromMsgBox(type, title, text);
  if (answer == null) {
    if (d == null || d.screens == null || title != 'Connection Error') return false;
    if (d.finished) return true;
    // The link dropped while the customer was being asked: no quiet retry into a control session.
    if (d.asked) {
      _finish(ffi, kDemoDropped);
      return true;
    }
    return false;
  }
  d?.reply?.cancel();
  if (answer.waiting) {
    _showWait(ffi, answer.text);
    return true;
  }
  if (answer.accepted) {
    // The customer's PC connects back to this app; its window is the red bar. This window has done its part.
    d?.finished = true;
    ffi.dialogManager.dismissByTag(_tag(ffi));
    closeConnection(id: ffi.id);
    return true;
  }
  _finish(ffi, answer.text);
  return true;
}

// ---- the technician: the red bar (his connection-manager window) ----

/// The size of the technician's connection-manager window while it is the red bar, at the top centre of his screen.
const kDolphinDemoBarSize = Size(560, 44);

/// The technician app's connection-manager window: its only incoming connection is a demo (src/dolphin_demo_core.rs),
/// so the window is the always-on-top red bar instead of upstream's card. «پایان دمو» ends the connection.
class DolphinDemoBarHost extends StatefulWidget {
  const DolphinDemoBarHost({super.key});

  @override
  State<DolphinDemoBarHost> createState() => _DolphinDemoBarHostState();
}

class _DolphinDemoBarHostState extends State<DolphinDemoBarHost> {
  Timer? _tick;
  DateTime? _since;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    gFFI.serverModel.addListener(_changed);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
      _keepBar();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    gFFI.serverModel.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Upstream sets its own size when the window shows; the bar takes its place back.
  Future<void> _keepBar() async {
    final size = await windowManager.getSize();
    if (size == kDolphinDemoBarSize) return;
    await windowManager.setSizeAlignment(kDolphinDemoBarSize, Alignment.topCenter);
    await windowManager.setAlwaysOnTop(true);
  }

  Future<void> _closeEnded(List<Client> ended) async {
    if (_closing) return;
    _closing = true;
    try {
      for (final c in ended) {
        await bind.cmRemoveDisconnectedConnection(connId: c.id);
      }
      if (await bind.cmGetClientsLength() == 0) await windowManager.close();
    } finally {
      _closing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clients = gFFI.serverModel.clients;
    final live = clients.where((c) => c.authorized && !c.disconnected).toList();
    final ended = clients.where((c) => c.disconnected).toList();
    if (ended.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _closeEnded(ended));
    if (live.isEmpty) return const ColoredBox(color: DolphinDemoBar.red);
    final c = live.first;
    _since ??= DateTime.now();
    return Material(
      color: DolphinDemoBar.red,
      child: DolphinDemoBar(
        peerName: c.name.isEmpty ? c.peerId : c.name,
        elapsed: DateTime.now().difference(_since!),
        onEnd: () {
          for (final l in live) {
            bind.cmCloseConnection(connId: l.id);
          }
        },
      ),
    );
  }
}

// ---- the customer: the demo window ----

/// The customer app is incoming-only: its only outgoing session is upstream's switch-back, which only a demo starts
/// (src/dolphin_demo_core.rs). So every session window of the customer app is the demo window.
bool isDolphinDemoWindow() => bind.isIncomingOnly();

/// The technician's name the portal vouched for, or his ID.
String _technician(String peerId) {
  String opt(String key) => bind.mainGetOptionSync(key: key);
  final name = opt(kDolphinTechNameOption);
  return opt(kDolphinTechIdOption) == peerId && name.isNotEmpty && name != '-' ? name : peerId;
}

/// The demo window's strip in place of the session toolbar (D2): whose screen, «فقط تماشا», his screens when he
/// allowed them all, «پایان دمو». It also names the window «دمو از دلفین — …».
class DolphinDemoWindowStrip extends StatefulWidget {
  final FFI ffi;
  final String peerId;
  const DolphinDemoWindowStrip({super.key, required this.ffi, required this.peerId});

  @override
  State<DolphinDemoWindowStrip> createState() => _DolphinDemoWindowStripState();
}

class _DolphinDemoWindowStripState extends State<DolphinDemoWindowStrip> {
  late final String _title = demoWindowTitle(_technician(widget.peerId));

  @override
  void initState() {
    super.initState();
    final windowId = stateGlobal.windowId;
    if (windowId >= 0) WindowController.fromWindowId(windowId).setTitle(_title);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.ffi.ffiModel,
        builder: (context, _) {
          final pi = widget.ffi.ffiModel.pi;
          final all = pi.platformAdditions[kDolphinDemoScreensAddition] == 'all';
          return Align(
            alignment: Alignment.bottomCenter,
            child: DolphinDemoWindowBar(
              title: _title,
              screens: all ? pi.displays.length : 1,
              current: pi.currentDisplay,
              onScreen: all ? (i) => openMonitorInTheSameTab(i, widget.ffi, pi) : null,
              onEnd: () => closeConnection(id: widget.peerId),
            ),
          );
        },
      );
}

/// The customer's demo window: the end of the connection, or a failure to connect, in one Persian dialog with
/// «بستن», never upstream's error box or a retry. True: taken.
bool dolphinDemoWindowMsgBox(FFI? ffi, dynamic type, dynamic title, dynamic text) {
  if (ffi == null || !isDolphinDemoWindow()) return false;
  if (title != 'Connection Error' && !(type is String && type.contains('error'))) return false;
  final tag = '${ffi.sessionId}-dolphin-demo-ended';
  ffi.dialogManager.dismissAll();
  ffi.dialogManager.show(
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: DolphinDemoEndedView(wasConnected: ffi.ffiModel.pi.isSet.value, onClose: () => closeConnection(id: ffi.id)),
    ),
    tag: tag,
  );
  return true;
}
