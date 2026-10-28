import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import '../common/formatter/id_formatter.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'brand.dart';
import 'customer_requests.dart';
import 'home_view.dart';
import 'panel_bridge.dart';

/// Pushed by the portal with every heartbeat (app/src/lib/engine/policy.ts SUPPORT_PHONE_OPTION),
/// so admins change the numbers without a new release.
const kDolphinSupportPhoneOption = 'dolphin-support-phone';

/// The ID screen's content size; upstream adds the title bar (common.dart getIncomingOnlyHomeSize).
const kDolphinHomeSize = Size(320, 400);

/// The request section needs room for the portal's pages.
const kDolphinRequestsSize = Size(980, 720);

/// Customer build's main window: the ID screen, or the request section (the customer portal).
class DolphinHome extends StatefulWidget {
  const DolphinHome({super.key});

  @override
  State<DolphinHome> createState() => _DolphinHomeState();
}

class _DolphinHomeState extends State<DolphinHome> {
  bool _requests = false;
  Timer? _options;
  // Authorised remote sessions, from the server (see connectedCount). Read with the 2 s timer.
  int _connected = 0;

  @override
  void initState() {
    super.initState();
    // Upstream sizes the incoming-only window from its own home page, which this build does not show.
    imcomingOnlyHomeSize = kDolphinHomeSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitWindow());
    // Options the portal pushes (support phone, whether to show the code) change without the server model noticing.
    _options = Timer.periodic(const Duration(seconds: 2), (_) async {
      final n = connectedCount(await bind.mainGetConnectStatus());
      if (mounted) setState(() => _connected = n);
    });
  }

  @override
  void dispose() {
    _options?.cancel();
    super.dispose();
  }

  Future<void> _fitWindow() async {
    if (_requests) {
      setResizable(true);
      await windowManager.setSize(kDolphinRequestsSize);
      await windowManager.center();
    } else {
      await windowManager.setSize(getIncomingOnlyHomeSize());
      setResizable(false);
    }
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
            inSession: _connected > 0);
        if (_requests) return DolphinCustomerRequests(id: id, code: code, onBack: () => _show(false));
        return DolphinHomeView(
          id: id,
          code: code,
          onCopyCode: () {
            Clipboard.setData(ClipboardData(text: code));
            showToast('کپی شد');
          },
          state: serverStateFromStatus(model.connectStatus),
          phone: supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone),
          siteLabel: DolphinBrand.siteLabel,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: id));
            showToast('کپی شد');
          },
          onRequests: () => _show(true),
        );
      }),
    );
  }
}
