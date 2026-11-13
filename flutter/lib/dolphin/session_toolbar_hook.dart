import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../common/shared_state.dart';
import '../common/widgets/dialog.dart';
import '../common/widgets/toolbar.dart';
import '../consts.dart';
import '../models/model.dart';
import '../models/platform_model.dart';
import 'monitor_picker.dart';
import 'no_picture.dart';
import 'session_toolbar.dart';

/// Plan 18 Phase 3 merge point for p3-panel: «عکس صفحه» (DD-51) and «زبان صفحه‌کلید» (DD-6) in the session bar.
/// Set these once (e.g. in the remote window's start-up); null leaves the buttons disabled with «(به‌زودی)».
class DolphinToolbarHooks {
  static void Function(BuildContext context, FFI ffi)? onScreenshot;
  static void Function(BuildContext context, FFI ffi)? onKeyboardLayout;
}

/// Upstream's rule for Ctrl+Alt+Del (toolbarControls in common/widgets/toolbar.dart): a normal session, input allowed and
/// not view-only, and a PC that can take it (Linux, or Windows with the installed service: `sasEnabled`).
bool dolphinCanCtrlAltDel(FFI ffi) {
  final m = ffi.ffiModel;
  return ffi.connType == ConnType.defaultConn &&
      !m.viewOnly &&
      m.keyboard &&
      (m.pi.platform == kPeerPlatformLinux || m.pi.sasEnabled);
}

/// The customer's app says whether it is installed (`platform_additions.is_installed`); null when it did not.
bool? dolphinPeerInstalled(FFI ffi) {
  final v = ffi.ffiModel.pi.platformAdditions['is_installed'];
  return v is bool ? v : null;
}

/// DD-16, hooked into upstream's «وصل شد؛ در انتظار تصویر…» dialog (`showConnectedWaitingForImage`, models/model.dart):
/// upstream's text and «قطع» first, the lock-screen help after a few seconds without a picture.
Widget dolphinWaitingForPicture(FFI? ffi, Widget upstream, VoidCallback onClose) => DolphinWaitingForPicture(
      waiting: upstream,
      canCtrlAltDel: ffi != null && dolphinCanCtrlAltDel(ffi),
      installed: ffi == null ? null : dolphinPeerInstalled(ffi),
      onCtrlAltDel: ffi == null ? null : () => bind.sessionCtrlAltDel(sessionId: ffi.sessionId),
      onDisconnect: onClose,
    );

/// DD-16 from the toolbar's «؟»: the same help over a picture that shows the sign-in screen or froze.
void showDolphinNoPictureHelp(FFI ffi) {
  ffi.dialogManager.show(
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: DolphinNoPictureHelp(
        canCtrlAltDel: dolphinCanCtrlAltDel(ffi),
        installed: dolphinPeerInstalled(ffi),
        onCtrlAltDel: () {
          bind.sessionCtrlAltDel(sessionId: ffi.sessionId);
          close();
        },
        onWait: close,
        onDisconnect: () {
          close();
          clientClose(ffi.sessionId, ffi); // upstream's close, with its own confirmation
        },
      ),
      onCancel: close,
    ),
    tag: '${ffi.sessionId}-dolphin-no-picture',
  );
}

/// DD-28: the session bar, built from the session; added first to upstream's toolbar (desktop/widgets/remote_toolbar.dart,
/// marked `Dolphin Connect (DD-28)`). Every action is one upstream already has in its menus, called the same way.
class DolphinToolbarHook extends StatefulWidget {
  final String id;
  final FFI ffi;
  final Axis axis;
  final VoidCallback? onCollapse;
  const DolphinToolbarHook({super.key, required this.id, required this.ffi, this.axis = Axis.horizontal, this.onCollapse});

  @override
  State<DolphinToolbarHook> createState() => _DolphinToolbarHookState();
}

class _DolphinToolbarHookState extends State<DolphinToolbarHook> {
  FFI get ffi => widget.ffi;
  FfiModel get m => ffi.ffiModel;
  PeerInfo get pi => m.pi;

  static const _follow = 'follow-remote-window';

  /// Upstream's rule for «Follow remote window focus» (toolbarCursor in common/widgets/toolbar.dart).
  bool get _canFollow =>
      pi.platform != kPeerPlatformAndroid &&
      !ffi.canvasModel.cursorEmbedded &&
      !pi.isWayland &&
      versionCmp(pi.version, '1.2.4') >= 0 &&
      pi.displays.length > 1 &&
      pi.currentDisplay != kAllDisplayValue &&
      !bind.sessionIsMultiUiSession(sessionId: ffi.sessionId);

  /// Upstream hides the monitor menu while a privacy mode forbids switching (remote_toolbar.dart _buildToolbar).
  int get _screens {
    final privacy = PrivacyModeState.find(widget.id);
    final allowed = privacy.isEmpty || allowDisplaySwitchInPrivacyMode(pi, privacy.value);
    return allowed ? pi.displaysCount.value : 1;
  }

  /// As upstream's «View Mode» item (_KeyboardMenu.viewMode).
  Future<void> _toggleViewOnly() async {
    await bind.sessionToggleOption(sessionId: ffi.sessionId, value: kOptionToggleViewOnly);
    final viewOnly = await bind.sessionGetToggleOption(sessionId: ffi.sessionId, arg: kOptionToggleViewOnly);
    m.setViewOnly(widget.id, viewOnly ?? !m.viewOnly);
    final showMyCursor = await bind.sessionGetToggleOption(sessionId: ffi.sessionId, arg: kOptionToggleShowMyCursor);
    m.setShowMyCursor(showMyCursor ?? m.showMyCursor);
  }

  /// As upstream's «Show my cursor» item (_KeyboardMenu.showMyCursor), which also turns view-only on.
  Future<void> _toggleMyCursor() async {
    await bind.sessionToggleOption(sessionId: ffi.sessionId, value: kOptionToggleShowMyCursor);
    final showMyCursor =
        await bind.sessionGetToggleOption(sessionId: ffi.sessionId, arg: kOptionToggleShowMyCursor) ?? !m.showMyCursor;
    m.setShowMyCursor(showMyCursor);
    if (showMyCursor && !m.viewOnly) {
      await bind.sessionToggleOption(sessionId: ffi.sessionId, value: kOptionToggleViewOnly);
      final viewOnly = await bind.sessionGetToggleOption(sessionId: ffi.sessionId, arg: kOptionToggleViewOnly);
      m.setViewOnly(widget.id, viewOnly ?? true);
    }
  }

  Future<void> _toggleFollow() async {
    await bind.sessionToggleOption(sessionId: ffi.sessionId, value: _follow);
    if (mounted) setState(() {});
  }

  /// As upstream's «Transfer file» item: a file-transfer window to the same PC with this session's token.
  void _files() => connect(context, widget.id,
      isFileTransfer: true, connToken: bind.sessionGetConnToken(sessionId: ffi.sessionId));

  /// As upstream's monitor buttons (_MonitorMenu.onPressed).
  void _pickScreen(int i) {
    final current = CurrentDisplayState.find(widget.id);
    if (current.value == i) return;
    final individual =
        pi.isSupportMultiDisplay && bind.sessionGetDisplaysAsIndividualWindows(sessionId: ffi.sessionId) == 'Y';
    if (individual) {
      openMonitorInNewTabOrWindow(i, ffi.id, pi);
    } else {
      openMonitorInTheSameTab(i, ffi, pi);
    }
  }

  Widget _picker(BuildContext context, VoidCallback close) => DolphinMonitorPicker(
        screens: [
          for (final d in pi.displays)
            DolphinScreen(
                x: d.x,
                y: d.y,
                width: d.width / d.scale,
                height: d.height / d.scale,
                pixelWidth: d.width,
                pixelHeight: d.height),
        ],
        current: CurrentDisplayState.find(widget.id).value,
        primary: pi.primaryDisplay >= 0 ? pi.primaryDisplay : null,
        onPick: (i) {
          close();
          _pickScreen(i);
        },
      );

  @override
  Widget build(BuildContext context) {
    if (ffi.connType != ConnType.defaultConn) return const SizedBox.shrink();
    return Obx(() {
      final screens = _screens; // reads the Rx counts inside Obx
      return ListenableBuilder(
        listenable: Listenable.merge([m, ffi.qualityMonitorModel]),
        builder: (context, _) {
          final input = !m.viewOnly && m.keyboard;
          final shot = DolphinToolbarHooks.onScreenshot;
          final layout = DolphinToolbarHooks.onKeyboardLayout;
          return DolphinSessionBar(
            axis: widget.axis,
            state: DolphinBarState(
              latencyMs: parseDelay(ffi.qualityMonitorModel.data.delay),
              direct: m.direct,
              viewOnly: m.viewOnly,
              myCursor: m.showMyCursor,
              follow: _canFollow && bind.sessionGetToggleOptionSync(sessionId: ffi.sessionId, arg: _follow),
              canFollow: _canFollow,
              screens: screens,
            ),
            onCtrlAltDel: dolphinCanCtrlAltDel(ffi) ? () => bind.sessionCtrlAltDel(sessionId: ffi.sessionId) : null,
            onLock: input ? () => bind.sessionLockScreen(sessionId: ffi.sessionId) : null,
            onFiles: isDesktop ? _files : null,
            onViewOnly: versionCmp(pi.version, '1.2.0') >= 0 && m.keyboard ? _toggleViewOnly : null,
            onMyCursor: [kPeerPlatformWindows, kPeerPlatformMacOS, kPeerPlatformLinux].contains(pi.platform)
                ? _toggleMyCursor
                : null,
            onFollow: _toggleFollow,
            onNoPicture: () => showDolphinNoPictureHelp(ffi),
            onCollapse: widget.onCollapse,
            screensMenu: _picker,
            // ---- p3-panel (DD-51, DD-6)
            onScreenshot: shot == null ? null : () => shot(context, ffi),
            onKeyboardLayout: layout == null ? null : () => layout(context, ffi),
            // ---- end p3-panel
          );
        },
      );
    });
  }
}
