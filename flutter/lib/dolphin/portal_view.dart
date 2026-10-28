import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import 'brand.dart';
import 'panel_bridge.dart';
import 'theme.dart';

/// Lets the screen around a portal page send it a message (the technician app's own field, WF-2).
class DolphinPortalLink {
  Future<void> Function(String message)? _send;

  /// Sends [message] to the page; false while the page is not loaded (or WebView2 is missing).
  Future<bool> send(String message) async {
    final send = _send;
    if (send == null) return false;
    await send(message);
    return true;
  }
}

/// A portal page inside the app (WebView2): the staff panel in the technician app, the customer
/// portal in the customer app. It stays on the portal and hands the page's messages to [onMessage];
/// a non-null answer is posted back to the page.
class DolphinPortalView extends StatefulWidget {
  final String path;
  final Future<String?> Function(PanelMessage message) onMessage;

  final DolphinPortalLink? link;

  const DolphinPortalView({super.key, required this.path, required this.onMessage, this.link});

  @override
  State<DolphinPortalView> createState() => _DolphinPortalViewState();
}

class _DolphinPortalViewState extends State<DolphinPortalView> {
  final _web = WebviewController();
  final _subs = <StreamSubscription>[];
  bool _ready = false;
  bool _noWebView = false;

  String get _home => '${DolphinBrand.portalUrl}${widget.path}';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
      widget.link?._send = _web.postWebMessage;
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _noWebView = true);
    }
  }

  Future<void> _onMessage(dynamic raw) async {
    final m = parsePanelMessage(raw);
    if (m == null || !mounted) return;
    final reply = await widget.onMessage(m);
    if (reply != null && mounted) await _web.postWebMessage(reply);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    widget.link?._send = null;
    _web.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_noWebView) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'نمایش این بخش در برنامه به «Microsoft Edge WebView2» نیاز دارد. آن را نصب کنید، یا همین صفحه را در مرورگر باز کنید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DolphinColors.muted, height: 1.8),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => launchUrl(Uri.parse(_home)),
                child: const Text('باز کردن در مرورگر'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Webview(_web);
  }
}
