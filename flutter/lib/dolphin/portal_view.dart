import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

import 'brand.dart';
import 'panel_bridge.dart';
import 'signin_expired.dart';
import 'theme.dart';

/// Lets the screen around a portal page send it a message (the technician app's own field, WF-2).
class DolphinPortalLink {
  Future<void> Function(String message)? _send;
  bool Function()? _onPortal;
  bool Function()? _loaded;

  /// A portal page has finished loading (the side pane waits for it before it hands over a screenshot, DD-51).
  bool get loaded => (_onPortal?.call() ?? false) && (_loaded?.call() ?? false);

  /// Sends [message] to the page; false while the page is not loaded (or WebView2 is missing).
  Future<bool> send(String message) async {
    final send = _send;
    if (send == null || !(_onPortal?.call() ?? false)) return false;
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
  String _url = '';
  bool _loaded = false;

  // DD-15: the staff sign-in expired mid-use (signin_expired.dart); the last panel page, to return to after it.
  bool _expired = false;
  String? _lastPage;
  bool get _staff => widget.path.startsWith('/staff');

  bool get _onPortal => isPortalPage(_url, DolphinBrand.portalUrl);

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
        _url = url;
        if (!isPanelUrl(url, DolphinBrand.portalUrl)) _web.loadUrl(_home);
        if (_staff && _onPortal && signInExpiredAt(url, DolphinBrand.portalUrl) && mounted) {
          setState(() => _expired = true); // DD-15
        }
      }));
      if (_staff) _subs.add(_web.loadingState.listen(_onLoaded)); // DD-15
      _subs.add(_web.webMessage.listen(_onMessage));
      _subs.add(_web.loadingState.listen((state) => _loaded = state == LoadingState.navigationCompleted));
      await _web.loadUrl(_home);
      widget.link?._send = _web.postWebMessage;
      widget.link?._onPortal = () => _onPortal;
      widget.link?._loaded = () => _loaded;
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _noWebView = true);
    }
  }

  /// DD-15: after each page, a 401 means the sign-in expired; a panel page that loaded is where to come back to.
  Future<void> _onLoaded(LoadingState state) async {
    if (state != LoadingState.navigationCompleted || !_onPortal) return;
    final url = _url;
    int status = 0;
    try {
      final s = await _web.executeScript(kNavigationStatusScript);
      status = s is num ? s.toInt() : int.tryParse('$s') ?? 0;
    } catch (_) {} // no status: only the address is used
    if (!mounted || url != _url) return;
    if (signInExpiredAt(url, DolphinBrand.portalUrl, status: status)) {
      setState(() => _expired = true);
    } else if (isStaffPanelPage(url, DolphinBrand.portalUrl)) {
      _lastPage = url;
      if (_expired) setState(() => _expired = false); // signed in again
    }
  }

  void _signInAgain() {
    final onLogin = isStaffLoginPage(_url, DolphinBrand.portalUrl);
    setState(() => _expired = false);
    // On the portal's own sign-in page (with its `next`) the form is already there; otherwise go to it.
    if (!onLogin) _web.loadUrl(signInAgainUrl(DolphinBrand.portalUrl, _lastPage));
  }

  Future<void> _onMessage(dynamic raw) async {
    final m = parsePanelMessage(raw);
    // Only our portal page is heard; a foreign top-level page may load before the redirect home happens.
    if (m == null || !mounted || !_onPortal) return;
    final reply = await widget.onMessage(m);
    if (reply != null && mounted && _onPortal) await _web.postWebMessage(reply);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    widget.link?._send = null;
    widget.link?._onPortal = null;
    widget.link?._loaded = null;
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
              Text(
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
    // DD-15: the notice covers the panel (the WebView is a texture, so Flutter draws over it); one tree either way, so
    // the WebView is never rebuilt.
    return Stack(children: [
      Webview(_web),
      if (_expired) Positioned.fill(child: DolphinSignInExpired(onSignIn: _signInAgain)),
    ]);
  }
}
