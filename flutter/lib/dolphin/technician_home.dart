import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'home_view.dart';
import 'panel_bridge.dart';
import 'portal_view.dart';
import 'theme.dart';

/// The technician build's main window: own ID, a manual connect field, and the staff panel.
class DolphinTechnicianHome extends StatefulWidget {
  const DolphinTechnicianHome({super.key});

  @override
  State<DolphinTechnicianHome> createState() => _DolphinTechnicianHomeState();
}

class _DolphinTechnicianHomeState extends State<DolphinTechnicianHome> {
  final _manual = TextEditingController();
  String _myId = '';

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
    if (m.type == 'dolphin-connect' && mounted) connect(context, m.id);
    return null;
  }

  void _connectManual() {
    final id = _manual.text.replaceAll(' ', '');
    if (panelIdPattern.hasMatch(id)) connect(context, id);
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(DolphinRadii.field),
        borderSide: const BorderSide(color: DolphinColors.lineStrong));
    return Directionality(
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
                  onPressed: _connectManual,
                  child: const Text('اتصال'),
                ),
              ],
            ),
          ),
          Expanded(child: DolphinPortalView(path: '/staff/computers', onMessage: _onMessage)),
        ],
      ),
    );
  }
}
