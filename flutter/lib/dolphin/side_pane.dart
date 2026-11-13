import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../common.dart';
import '../consts.dart';
import '../models/model.dart';
import '../models/platform_model.dart';
import 'panel_bridge.dart';
import 'portal_view.dart';
import 'session_toolbar_hook.dart';
import 'side_panel.dart';
import 'theme.dart';

/// Plan 18 Phase 3 in the technician's remote window (rules in side_panel.dart): the portal's panel for this PC beside
/// the picture (DD-49), «چسباندن» from it (DD-50), «عکس صفحه» to the open call (DD-51) and the customer's keyboard
/// language (DD-6). One per remote tab, bound to that tab's session and peer: nothing it does reaches another session.
///
/// The toolbar (p3-toolbar) can call [DolphinSessionPanel.of] with the tab's FFI: [toggle], [screenshot],
/// [setKeyboard]. Until then the small strip at the picture's right edge has the three buttons.
class DolphinSessionPanel extends ChangeNotifier {
  final FFI ffi;
  final String peerId;
  final link = DolphinPortalLink();

  DolphinSessionPanel(this.ffi, this.peerId, {bool open = false}) : _open = open;

  static final _panels = Expando<DolphinSessionPanel>('dolphin-side');

  /// The panel of the remote tab with this session, or null (customer build, no tab, not Windows).
  static DolphinSessionPanel? of(FFI ffi) => _panels[ffi];

  bool _open;
  bool get open => _open;
  String? _notice;
  String? get notice => _notice;
  bool _noticeOk = true;
  bool get noticeOk => _noticeOk;
  bool _shotPending = false;
  bool get shotPending => _shotPending;
  Timer? _noticeTimer;
  Timer? _replyTimer;
  Timer? _shotTimer;
  bool _disposed = false;

  void attach() {
    _panels[ffi] = this;
    ffi.ffiModel.dolphinMsgBoxHook = _onMsgBox;
    ffi.ffiModel.dolphinScreenshotHook = _onScreenshot;
    _applyInset();
  }

  void detach() {
    if (identical(_panels[ffi], this)) _panels[ffi] = null;
    if (ffi.ffiModel.dolphinMsgBoxHook == _onMsgBox) ffi.ffiModel.dolphinMsgBoxHook = null;
    if (ffi.ffiModel.dolphinScreenshotHook == _onScreenshot) ffi.ffiModel.dolphinScreenshotHook = null;
    ffi.canvasModel.dolphinRightInset = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    _replyTimer?.cancel();
    _shotTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  SessionState get _state => SessionState(
        live: !ffi.closed && ffi.ffiModel.pi.isSet.value && !ffi.ffiModel.waitForFirstImage.value,
        keyboard: ffi.ffiModel.keyboard,
        clipboard: ffi.ffiModel.permissions['clipboard'] != false,
        viewOnly: ffi.ffiModel.viewOnly,
        paused: ffi.ffiModel.dolphinPaused,
      );

  void say(String text, {bool ok = true}) {
    _notice = text;
    _noticeOk = ok;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      _notice = null;
      _changed();
    });
    _changed();
  }

  // DD-49: the pane.

  void toggle() => setOpen(!_open);

  void setOpen(bool open) {
    if (_open == open) return;
    _open = open;
    bind.mainSetLocalOption(key: kDolphinSideOption, value: open ? 'Y' : '');
    _applyInset();
    _changed();
  }

  /// The picture's area loses the pane's width (src: CanvasModel.getSize); the layout change itself makes the
  /// remote page recompute the view (_ViewStyleUpdater).
  void _applyInset() => ffi.canvasModel.dolphinRightInset = _open ? kDolphinSideWidth : 0;

  // DD-50: «چسباندن» from the pane.

  Future<String?> onPaneMessage(PanelMessage m) async {
    if (m.type != 'dolphin-paste') return null; // the pane answers nothing else: no ID, no code
    final problem = pasteProblem(m, peerId, _state);
    if (problem != null) {
      say(problem, ok: false);
      return null;
    }
    await bind.sessionSetCommon(sessionId: ffi.sessionId, key: kDolphinPasteKey, value: m.text);
    _waitReply();
    return null;
  }

  // DD-6: the customer's keyboard language.

  Future<void> setKeyboard(String lang) async {
    if (!kDolphinKeyboardChoices.any((c) => c.$1 == lang)) return;
    final problem = keyboardProblem(_state);
    if (problem != null) {
      say(problem, ok: false);
      return;
    }
    await bind.sessionSetCommon(sessionId: ffi.sessionId, key: kDolphinKeyboardKey, value: lang);
    _waitReply();
  }

  void _waitReply() {
    _replyTimer?.cancel();
    _replyTimer = Timer(kDolphinReplyWait, () => say(kNoReply, ok: false));
  }

  bool _onMsgBox(dynamic type, dynamic title, dynamic text) {
    final r = panelResultFromMsgBox(type, title, text);
    if (r == null) return false;
    _replyTimer?.cancel();
    say(r.$2, ok: r.$1);
    return true;
  }

  // DD-51: «عکس صفحه».

  /// Asks the customer's PC for a picture of the display shown here (upstream's screenshot request); the answer
  /// comes back through [_onScreenshot]. The pane opens, so the picture has somewhere to go.
  void screenshot() {
    if (_shotPending) return;
    final pi = ffi.ffiModel.pi;
    final problem = screenshotProblem(
      live: _state.live,
      supported: bind.sessionGetCommonSync(sessionId: ffi.sessionId, key: 'is_screenshot_supported', param: '') ==
          'true',
      allDisplays: pi.currentDisplay == kAllDisplayValue,
    );
    if (problem != null) {
      say(problem, ok: false);
      return;
    }
    setOpen(true);
    _shotPending = true;
    say(kShotTaking);
    bind.sessionTakeScreenshot(sessionId: ffi.sessionId, display: pi.currentDisplay);
    _shotTimer?.cancel();
    _shotTimer = Timer(kShotWait, () {
      _shotPending = false;
      say(kShotFailed, ok: false);
    });
  }

  bool _onScreenshot(Map<String, dynamic> evt) {
    if (!_shotPending) return false; // upstream's own menu item, if any, keeps its dialog
    _shotPending = false;
    _shotTimer?.cancel();
    final msg = evt['msg'];
    if (msg is String && msg.isNotEmpty) {
      say(msg.length > 160 ? kShotFailed : msg, ok: false);
    } else {
      _deliver();
    }
    return true;
  }

  /// The picture goes from upstream's cache to a temporary file, then to the pane; the file is deleted at once
  /// (no customer screen image is kept on the technician's PC; the portal keeps it with the call).
  Future<void> _deliver() async {
    Directory? dir;
    try {
      dir = await Directory.systemTemp.createTemp('dolphin-shot-');
      final path = '${dir.path}${Platform.pathSeparator}shot.png';
      final res = await bind.sessionHandleScreenshot(sessionId: ffi.sessionId, action: screenshotSaveAction(path));
      if (res.isNotEmpty) {
        say(kShotFailed, ok: false);
        return;
      }
      final png = await fitScreenshot(await File(path).readAsBytes());
      if (png == null) {
        say(kShotTooBig, ok: false);
        return;
      }
      final message = screenshotMessage(base64Encode(png), peerId);
      final sent = await _sendWhenLoaded(message);
      say(sent ? kShotSent : kShotNoPane, ok: sent);
    } catch (_) {
      say(kShotFailed, ok: false);
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// A pane just opened needs its page loaded and its script running before it hears anything.
  Future<bool> _sendWhenLoaded(String message) async {
    var waited = false;
    for (var i = 0; i < 80 && !link.loaded; i++) {
      waited = true;
      await Future.delayed(const Duration(milliseconds: 250));
      if (_disposed || !_open) return false;
    }
    if (!link.loaded) return false;
    if (waited) await Future.delayed(const Duration(milliseconds: 1500));
    return link.send(message);
  }
}

/// Scales a PNG down until its base64 fits the portal's limit; null when it cannot. Uses Flutter's own decoder and
/// encoder, on the technician's PC only.
Future<Uint8List?> fitScreenshot(Uint8List png) async {
  if (!isPng(png)) return null;
  if (screenshotFits(png.length)) return png;
  final probe = await (await ui.instantiateImageCodec(png)).getNextFrame();
  var width = probe.image.width;
  probe.image.dispose();
  var size = png.length;
  for (var i = 0; i < 4; i++) {
    final target = screenshotTargetWidth(size, width);
    if (target == null) return null;
    final frame = await (await ui.instantiateImageCodec(png, targetWidth: target)).getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) return null;
    final out = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (screenshotFits(out.length)) return out;
    width = target;
    size = out.length;
  }
  return null;
}

/// Wraps the remote page's body in the technician build: the picture, the strip and, when open, the pane.
class DolphinSessionSide extends StatefulWidget {
  final FFI ffi;
  final String peerId;
  final Widget child;
  const DolphinSessionSide({super.key, required this.ffi, required this.peerId, required this.child});

  @override
  State<DolphinSessionSide> createState() => _DolphinSessionSideState();
}

/// The session toolbar's «عکس صفحه» and «زبان صفحه‌کلید» (p3-toolbar, DolphinToolbarHooks) call this tab's panel. Set
/// once; a toolbar in a window without a panel (no technician build) finds none and does nothing.
void installDolphinPanelToolbarHooks() {
  DolphinToolbarHooks.onScreenshot ??= (context, ffi) => DolphinSessionPanel.of(ffi)?.screenshot();
  DolphinToolbarHooks.onKeyboardLayout ??= (context, ffi) async {
    final panel = DolphinSessionPanel.of(ffi);
    final box = context.findRenderObject() as RenderBox?;
    if (panel == null || box == null) return;
    final at = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final lang = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + box.size.width, at.dy),
      items: const [
        PopupMenuItem(value: 'fa', child: Text('فارسی', textDirection: TextDirection.rtl)),
        PopupMenuItem(value: 'en', child: Text('انگلیسی', textDirection: TextDirection.rtl)),
      ],
    );
    if (lang != null) await panel.setKeyboard(lang);
  };
}

class _DolphinSessionSideState extends State<DolphinSessionSide> {
  DolphinSessionPanel? _panel;

  @override
  void initState() {
    super.initState();
    // The technician build only (the customer's app has no staff panel), on Windows (WebView2), for a peer ID the
    // portal can know.
    if (isWindows && bind.isOutgoingOnly() && sidePanePath(widget.peerId) != null) {
      installDolphinPanelToolbarHooks();
      _panel = DolphinSessionPanel(widget.ffi, widget.peerId,
          open: sideOpenFrom(bind.mainGetLocalOption(key: kDolphinSideOption)))
        ..attach();
    }
  }

  @override
  void dispose() {
    _panel?.detach();
    _panel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = _panel;
    if (panel == null) return widget.child;
    return ListenableBuilder(
      listenable: panel,
      builder: (context, _) => DolphinSideLayout(
        open: panel.open,
        notice: panel.notice,
        noticeOk: panel.noticeOk,
        strip: DolphinSideStrip(
          open: panel.open,
          shotBusy: panel.shotPending,
          onToggle: panel.toggle,
          onScreenshot: panel.screenshot,
          onKeyboard: panel.setKeyboard,
        ),
        pane: panel.open
            ? DolphinSidePane(
                path: sidePanePath(panel.peerId)!,
                onMessage: panel.onPaneMessage,
                link: panel.link,
                onClose: () => panel.setOpen(false))
            : null,
        child: widget.child,
      ),
    );
  }
}

/// The picture on the left, the pane on the right (physical sides, whatever the text direction: the picture keeps its
/// left origin, so the pointer mapping stays as upstream has it).
class DolphinSideLayout extends StatelessWidget {
  final bool open;
  final Widget child;
  final Widget? pane;
  final Widget? strip;
  final String? notice;
  final bool noticeOk;
  const DolphinSideLayout(
      {super.key,
      required this.open,
      required this.child,
      this.pane,
      this.strip,
      this.notice,
      this.noticeOk = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            textDirection: TextDirection.ltr,
            children: [
              Positioned.fill(child: child),
              if (strip != null) Positioned(right: 4, top: 0, bottom: 0, child: Center(widthFactor: 1, child: strip)),
              if (notice != null)
                Positioned(top: 56, right: 48, child: DolphinSideNotice(text: notice!, ok: noticeOk)),
            ],
          ),
        ),
        if (open && pane != null) SizedBox(width: kDolphinSideWidth, child: pane),
      ],
    );
  }
}

/// One line over the picture: what the PC answered, or why nothing was sent.
class DolphinSideNotice extends StatelessWidget {
  final String text;
  final bool ok;
  const DolphinSideNotice({super.key, required this.text, this.ok = true});

  @override
  Widget build(BuildContext context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Material(
              elevation: 3,
              color: ok ? DolphinColors.aquaSoft : DolphinColors.amberSoft,
              borderRadius: BorderRadius.circular(DolphinRadii.control),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13, height: 1.6, color: ok ? DolphinColors.aquaText : DolphinColors.amberText)),
              ),
            ),
          ),
        ),
      );
}

// Dolphin Connect (Phase 3, p3-panel): own buttons until the toolbar merge; the toolbar's onScreenshot and
// onKeyboardLayout can call DolphinSessionPanel.of(ffi) instead, and this strip can then go.
class DolphinSideStrip extends StatelessWidget {
  final bool open;
  final bool shotBusy;
  final VoidCallback onToggle;
  final VoidCallback onScreenshot;
  final void Function(String lang) onKeyboard;
  const DolphinSideStrip(
      {super.key,
      required this.open,
      required this.onToggle,
      required this.onScreenshot,
      required this.onKeyboard,
      this.shotBusy = false});

  static const toggleKey = Key('dolphin-side-toggle');
  static const shotKey = Key('dolphin-side-shot');
  static const keyboardKey = Key('dolphin-side-keyboard');

  @override
  Widget build(BuildContext context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            elevation: 2,
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(DolphinRadii.control),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: toggleKey,
                  tooltip: open ? 'بستن پنل مشتری' : 'پنل مشتری',
                  isSelected: open,
                  color: open ? DolphinColors.azure : DolphinColors.muted,
                  icon: const Icon(Icons.view_sidebar_outlined),
                  onPressed: onToggle,
                ),
                IconButton(
                  key: shotKey,
                  tooltip: shotBusy ? 'در حال گرفتن عکس صفحه…' : 'عکس صفحه برای تماس',
                  color: DolphinColors.muted,
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: shotBusy ? null : onScreenshot,
                ),
                PopupMenuButton<String>(
                  key: keyboardKey,
                  tooltip: 'زبان صفحه‌کلید مشتری',
                  icon: const Icon(Icons.keyboard_outlined, color: DolphinColors.muted),
                  onSelected: onKeyboard,
                  itemBuilder: (context) => [
                    for (final c in kDolphinKeyboardChoices)
                      PopupMenuItem(
                          value: c.$1,
                          child: Directionality(textDirection: TextDirection.rtl, child: Text(c.$2))),
                  ],
                ),
              ]),
            ),
          ),
        ),
      );
}

/// The pane: a title with «بستن» and the portal page, in the same WebView2 profile as the main window's staff panel
/// (webview_windows keeps one user-data folder per program, %LOCALAPPDATA%\flutter_webview_windows\<exe name>), so
/// the staff sign-in is shared. DolphinPortalView keeps it on the portal's own origin.
class DolphinSidePane extends StatelessWidget {
  final String path;
  final Future<String?> Function(PanelMessage message) onMessage;
  final DolphinPortalLink link;
  final VoidCallback onClose;
  const DolphinSidePane(
      {super.key, required this.path, required this.onMessage, required this.link, required this.onClose});

  @override
  Widget build(BuildContext context) => DolphinLight(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: DecoratedBox(
            decoration: const BoxDecoration(border: BorderDirectional(end: BorderSide(color: DolphinColors.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                height: 40,
                padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
                color: DolphinColors.azureSoft,
                child: Row(children: [
                  const Expanded(
                      child: Text('پنل مشتری', style: TextStyle(fontWeight: FontWeight.bold, color: DolphinColors.ink))),
                  IconButton(
                      tooltip: 'بستن', icon: const Icon(Icons.close, size: 18), onPressed: onClose),
                ]),
              ),
              Expanded(child: DolphinPortalView(path: path, onMessage: onMessage, link: link)),
            ]),
          ),
        ),
      );
}
