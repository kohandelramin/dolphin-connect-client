import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'brand.dart';
import 'panel_bridge.dart';
import 'home_view.dart';
import 'theme.dart';

/// The technician build's main window: own ID, a manual connect field, and the staff panel.
class DolphinTechnicianHome extends StatefulWidget {
  const DolphinTechnicianHome({super.key});

  @override
  State<DolphinTechnicianHome> createState() => _DolphinTechnicianHomeState();
}

class _DolphinTechnicianHomeState extends State<DolphinTechnicianHome> {
  final _web = WebviewController();
  final _subs = <StreamSubscription>[];
  final _manual = TextEditingController();
  String _myId = '';
  bool _ready = false;
  bool _noWebView = false;

  String get _home => '${DolphinBrand.portalUrl}/staff/computers';

  @override
  void initState() {
    super.initState();
    bind.mainGetMyId().then((id) {
      if (mounted) setState(() => _myId = id);
    });
    _initWebView();
  }

  Future<void> _initWebView() async {
    try {
      if (await WebviewController.getWebViewVersion() == null) {
        if (mounted) setState(() => _noWebView = true);
        return;
      }
      await _web.initialize();
      await _web.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _subs.add(_web.url.listen((url) {
        if (!isPanelUrl(url, DolphinBrand.portalUrl)) _web.loadUrl(_home);
      }));
      _subs.add(_web.webMessage.listen(_onMessage));
      await _web.loadUrl(_home);
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _noWebView = true);
    }
  }

  Future<void> _onMessage(dynamic raw) async {
    final m = parsePanelMessage(raw);
    if (m == null || !mounted) return;
    if (m.type == 'dolphin-hello') {
      final id = _myId.isNotEmpty ? _myId : await bind.mainGetMyId();
      await _web.postWebMessage(jsonEncode({'type': 'dolphin-id', 'id': id}));
    } else if (m.type == 'dolphin-connect') {
      connect(context, m.id);
    }
  }

  void _connectManual() {
    final id = _manual.text.replaceAll(' ', '');
    if (panelIdPattern.hasMatch(id)) connect(context, id);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _web.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('دلفین کانکتِ کارشناس',
                    style: TextStyle(fontWeight: FontWeight.w800, color: DolphinColors.azure)),
                const SizedBox(width: 16),
                const Text('شناسه‌ی شما:', style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
                const SizedBox(width: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(_myId.isEmpty ? '…' : groupId(_myId),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: 'کپی شناسه',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: _myId.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _myId));
                          showToast('کپی شد');
                        },
                ),
                const Spacer(),
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: _manual,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(isDense: true, hintText: 'شناسه‌ی مشتری'),
                    onSubmitted: (_) => _connectManual(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: DolphinColors.azure),
                  onPressed: _connectManual,
                  child: const Text('اتصال'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: DolphinColors.line),
          Expanded(
            child: _noWebView
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'نمایش پنل در برنامه به «Microsoft Edge WebView2» نیاز دارد. آن را نصب کنید، یا پنل را در مرورگر باز کنید و شناسه‌ی مشتری را در کادر بالا وارد کنید.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : !_ready
                    ? const Center(child: CircularProgressIndicator())
                    : Webview(_web),
          ),
        ],
      ),
    );
  }
}
