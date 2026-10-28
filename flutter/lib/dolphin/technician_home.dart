import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'call_status.dart';
import 'home_view.dart';
import 'panel_bridge.dart';
import 'portal_view.dart';
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
      if (_call.answer(m.text, ok: m.ok) && m.ok) _manual.clear();
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
    final token = _call.waiting(); // busy before the send, so a second Enter cannot send a second call
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
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(DolphinRadii.field),
        borderSide: const BorderSide(color: DolphinColors.lineStrong));
    return ListenableBuilder(
      listenable: _call,
      builder: (context, _) => Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
                color: Colors.white, border: Border(bottom: BorderSide(color: DolphinColors.line))),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                const Text('دلفین کانکت',
                    style: TextStyle(fontWeight: FontWeight.w800, color: DolphinColors.azureStrong)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: DolphinColors.azureSoft, borderRadius: BorderRadius.circular(99)),
                  child: const Text('کارشناس',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DolphinColors.azureStrong)),
                ),
                const SizedBox(width: 16),
                const Text('شناسه‌ی شما', style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
                const SizedBox(width: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(_myId.isEmpty ? '…' : groupId(_myId),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'کپی شناسه',
                  icon: const Icon(Icons.copy, size: 16, color: DolphinColors.muted),
                  onPressed: _myId.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _myId));
                          showToast('کپی شد');
                        },
                ),
                const Spacer(),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _manual,
                    enabled: !_call.busy,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'شناسه‌ی مشتری',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: fieldBorder,
                      enabledBorder: fieldBorder,
                    ),
                    onSubmitted: (_) => _connectManual(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: DolphinColors.azure,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control))),
                  onPressed: _call.busy ? null : _connectManual,
                  child: const Text('اتصال'),
                ),
              ],
            ),
          ),
          if (_call.text != null) DolphinCallStatus(text: _call.text!, ok: _call.ok),
          Expanded(child: DolphinPortalView(path: '/staff/computers', onMessage: _onMessage, link: _panel)),
        ],
      ),
    ));
  }
}
