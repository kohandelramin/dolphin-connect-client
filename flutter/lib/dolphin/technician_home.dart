import 'package:flutter/material.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'call_status.dart';
import 'home_view.dart';
import 'panel_bridge.dart';
import 'portal_view.dart';
import 'technician_header.dart';
import 'theme.dart';

/// How long the field waits for the panel's answer before saying it got none.
const kDolphinCallWait = Duration(seconds: 8);

/// The technician build's main window: own ID, a manual connect field, and the staff panel.
class DolphinTechnicianHome extends StatefulWidget {
  const DolphinTechnicianHome({super.key});

  @override
  State<DolphinTechnicianHome> createState() => _DolphinTechnicianHomeState();
}

class _DolphinTechnicianHomeState extends State<DolphinTechnicianHome> {
  final _manual = TextEditingController();
  final _panel = DolphinPortalLink();
  String _myId = '';
  final _call = DolphinCallWait(kDolphinCallWait);

  @override
  void initState() {
    super.initState();
    bind.mainGetMyId().then((id) {
      if (mounted) setState(() => _myId = id);
    });
  }

  Future<String?> _onMessage(PanelMessage m) async {
    if (m.type == 'dolphin-hello') {
      return idReply(_myId.isNotEmpty ? _myId : await bind.mainGetMyId());
    }
    if (m.type == 'dolphin-connect' && mounted) {
      // In code mode the panel sends the customer's one-time code with the ID (WF-3).
      connect(context, m.id, password: m.code.isEmpty ? null : m.code);
    }
    if (m.type == 'dolphin-call-result') {
      if (_call.answer(m.text, ok: m.ok, id: m.id) && m.ok) _manual.clear();
    }
    return null;
  }

  /// The field never connects by itself: it asks the panel, which runs «اتصال» with all its checks (WF-2).
  Future<void> _connectManual() async {
    if (_call.busy) return;
    final problem = manualIdProblem(_manual.text);
    if (problem != null) {
      _call.show(problem, ok: false);
      return;
    }
    final id = _manual.text.replaceAll(' ', '');
    final token = _call.waiting(id: id); // busy before the send, so a second Enter cannot send a second call
    final sent = await _panel.send(callRequest(id));
    if (!sent && mounted && _call.isCurrent(token)) _call.show(kPanelNotReady, ok: false);
  }

  @override
  void dispose() {
    _call.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    return ListenableBuilder(
      listenable: _call,
      builder: (context, _) => Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          DolphinTechnicianHeader(myId: _myId, manual: _manual, call: _call, onConnect: _connectManual),
          if (_call.text != null) DolphinCallStatus(text: _call.text!, ok: _call.ok),
          Expanded(child: DolphinPortalView(path: '/staff/computers', onMessage: _onMessage, link: _panel)),
        ],
      ),
    ));
  }
}
