import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import '../consts.dart';
import '../common/formatter/id_formatter.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'brand.dart';
import 'callback.dart';
import 'customer_requests.dart';
import 'home_view.dart';
import 'panel_bridge.dart';
import 'recent_sessions.dart';
import 'tech_card.dart';
import 'verify.dart';
import 'window_sizes.dart';

/// Pushed by the portal with every heartbeat (app/src/lib/engine/policy.ts SUPPORT_PHONE_OPTION),
/// so admins change the numbers without a new release.
const kDolphinSupportPhoneOption = 'dolphin-support-phone';

/// The ID screen's content size; upstream adds the title bar (common.dart getIncomingOnlyHomeSize).
const kDolphinHomeSize = Size(320, 400);


/// Customer build's main window: the ID screen, or the request section (the customer portal).
class DolphinHome extends StatefulWidget {
  const DolphinHome({super.key});

  @override
  State<DolphinHome> createState() => _DolphinHomeState();
}

class _DolphinHomeState extends State<DolphinHome> {
  bool _requests = false;
  Timer? _options;
  // Authorised remote sessions, from the server (see connectedCount). Null until the first read: no code before that.
  int? _connected;
  // BL-SVC: the service was stopped (tray «توقف سرویس» before 2.0.0-rc.5, or an uninstall); the home then says so.
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    // Upstream sizes the incoming-only window from its own home page, which this build does not show.
    imcomingOnlyHomeSize = kDolphinHomeSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitWindow());
    // Options the portal pushes (support phone, whether to show the code) change without the server model noticing.
    // No immediate read: the count reaches the app about 1 s after the status sync starts, and an early read would be
    // the unsynced 0 (the code would flash during a session). The first read is the 2 s tick; until then it is unknown
    // and the code stays hidden (codeHiddenFor(null)).
    _options = Timer.periodic(const Duration(seconds: 2), (_) => _readConnected());
    _readStopped();
  }

  @override
  void dispose() {
    _options?.cancel();
    super.dispose();
  }

  Future<void> _readConnected() async {
    final n = connectedCount(await bind.mainGetConnectStatus());
    final stopped = await mainGetBoolOption(kOptionStopService);
    if (mounted) {
      setState(() {
        _connected = n;
        _stopped = stopped;
      });
    }
  }

  Future<void> _readStopped() async {
    final stopped = await mainGetBoolOption(kOptionStopService);
    if (mounted) setState(() => _stopped = stopped);
  }

  Future<void> _fitWindow() async {
    if (_requests) {
      setResizable(true);
      // UX-18: fit the screen (a 1366 × 768 laptop cannot take 980 × 720 plus the title bar).
      final displays = WidgetsBinding.instance.platformDispatcher.displays;
      final screen = displays.isEmpty ? kDolphinRequestsSize : displays.first.size / displays.first.devicePixelRatio;
      await windowManager.setSize(requestsSize(screen));
      await windowManager.center();
    } else {
      await windowManager.setSize(getIncomingOnlyHomeSize());
      setResizable(false);
    }
  }

  /// Plan 14 (B6): src/dolphin_callback.rs sends in the background; ask for its state until it has an answer.
  Future<CallbackStatus> _sendCallback(String name, String phone, String note) async {
    await bind.mainSetCommon(key: 'dolphin-callback-send', value: jsonEncode({'name': name, 'phone': phone, 'note': note}));
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final status = CallbackStatus.fromJson(await bind.mainGetCommon(key: 'dolphin-callback-state'));
      if (status.phase == CallbackPhase.done || status.phase == CallbackPhase.failed) return status;
    }
    return const CallbackStatus(CallbackPhase.failed, 'پاسخی نیامد؛ با پشتیبانی دلفین تماس بگیرید.');
  }

  void _openCallback() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: DolphinCallbackForm(onSend: _sendCallback, onClose: () => Navigator.of(context).pop()),
        ),
      ),
    );
  }

  /// Plan 14 (B5): who the portal has authorized for this PC, until they connect.
  TechComing? _coming() {
    String opt(String key) => bind.mainGetOptionSync(key: key);
    return techComing(
      techId: opt(kDolphinTechIdOption),
      techName: opt(kDolphinTechNameOption),
      until: int.tryParse(opt(kDolphinTechUntilOption)) ?? 0,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      connected: _connected,
      photo: opt(kDolphinTechPhotoOption),
    );
  }

  void _show(bool requests) {
    setState(() => _requests = requests);
    _fitWindow();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        // serverId is declared as a TextEditingController but built as the ID controller (server_model.dart).
        final id = trimID(model.serverId.text);
        final code = dolphinCode(
            approveMode: model.approveMode,
            showCode: bind.mainGetOptionSync(key: kDolphinShowCodeOption),
            password: model.serverPasswd.text,
            inSession: codeHiddenFor(_connected));
        if (_requests) return DolphinCustomerRequests(id: id, code: code, onBack: () => _show(false));
        return DolphinHomeView(
          id: id,
          code: code,
          onCopyCode: () {
            Clipboard.setData(ClipboardData(text: code));
            showToast('کپی شد');
          },
          state: serverStateFromStatus(model.connectStatus, serviceStopped: _stopped),
          // Upstream's own action: clears `stop-service`, which on an installed app recreates and starts the Windows
          // service (UAC prompt); the 2 s read then shows the new state.
          onStartService: () => start_service(true),
          phone: supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone),
          siteLabel: DolphinBrand.siteLabel,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: id));
            showToast('کپی شد');
          },
          onRequests: () => _show(true),
          recent: parseRecentSessions(bind.mainGetOptionSync(key: kDolphinRecentSessionsOption)),
          coming: _connected == null ? null : _coming(),
          onCallback: callbackShown(bind.mainGetOptionSync(key: kDolphinCallbackOption)) ? _openCallback : null,
        );
      }),
    );
  }
}
