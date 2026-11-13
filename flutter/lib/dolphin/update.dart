import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart' hide Dialog;
import '../models/platform_model.dart';
import 'brand.dart';
import 'tech_theme.dart';
import 'theme.dart';
import 'theme_option.dart';
import 'update_check.dart';
import 'update_view.dart';

const kDolphinUpdateSize = Size(500, 440); // Plan 19: the popup card with room around it

/// Plan 19: the technician app's answer from this start, shown once as a popup over its home (tech_ui/technician_app.dart).
DolphinUpdateCheck? dolphinPendingTechUpdate;

/// TB-20, Plan 19: runs at every start, before the main window opens, and asks the portal for the newest build
/// (at most about 4 s; no answer opens the app, D12). Customer app: a newer build is required (D10), the update popup
/// takes the window and the app opens after it; returns true then. Technician app: the app opens as usual and the
/// popup («به‌روزرسانی» / «بعداً») shows over it; returns false.
///
/// [openApp] opens the normal home page; it runs when the customer taps «ادامه با همین نسخه» after a failure (D19).
Future<bool> runDolphinUpdateIfNeeded(Future<void> Function() openApp) async {
  if (!isWindows) return false; // the update screen is a Windows desktop screen
  final check = DolphinUpdateCheck.fromJson(await bind.mainGetCommon(key: 'dolphin-update-check'));
  switch (startUpdateAction(check, technician: bind.isOutgoingOnly())) {
    case StartUpdate.open:
      return false;
    case StartUpdate.ask:
      dolphinPendingTechUpdate = check;
      return false;
    case StartUpdate.required:
      break;
  }
  themeFromMainWindow(); // the portal's theme as the main window last applied it (Plan 19)
  await windowManager.setPreventClose(false);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: DolphinBrand.appNameFa,
    theme: dolphinTheme(ThemeData.light()),
    home: Scaffold(body: DolphinUpdateScreen(check: check, openApp: openApp)),
  ));
  await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: kDolphinUpdateSize, center: true, title: DolphinBrand.appNameFa), () async {
    await windowManager.setOpacity(1);
    await windowManager.show();
    await windowManager.focus();
  });
  return true;
}

class DolphinUpdateScreen extends StatefulWidget {
  final DolphinUpdateCheck check;
  final Future<void> Function() openApp;

  /// DD-20: the same screen in a dialog of the running app. «بستن» and «ادامه با همین نسخه» close the dialog
  /// ([onClose], [openApp]) instead of the window; the window's close handling is left as it is.
  final bool inApp;
  final VoidCallback? onClose;
  const DolphinUpdateScreen(
      {super.key, required this.check, required this.openApp, this.inApp = false, this.onClose});

  @override
  State<DolphinUpdateScreen> createState() => _DolphinUpdateScreenState();
}

class _DolphinUpdateScreenState extends State<DolphinUpdateScreen> {
  late DolphinUpdateCheck _check = widget.check;
  DolphinUpdateProgress _progress = DolphinUpdateProgress.idle;
  Timer? _timer;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    if (_check.state == 'update') _kick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _kick() {
    _timer?.cancel();
    _applying = false;
    bind.mainSetCommon(key: 'dolphin-update-start', value: '');
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _poll());
  }

  void _retry() {
    setState(() {
      _check = DolphinUpdateCheck(
          state: 'update',
          version: _check.version,
          lead: _check.lead,
          phone: _check.phone,
          downloadPage: _check.downloadPage);
      _progress = DolphinUpdateProgress.idle;
    });
    _kick();
  }

  void _poll() {
    final p = DolphinUpdateProgress.fromJson(bind.mainGetCommonSync(key: 'dolphin-update-progress'));
    if (!mounted) return;
    setState(() => _progress = p);
    if (p.state == 'ready' && !_applying) {
      _applying = true;
      // Swaps the file in and restarts the app; comes back only on failure, which the next poll shows.
      bind.mainSetCommon(key: 'dolphin-update-apply', value: '');
    } else if (p.state == 'failed') {
      _timer?.cancel();
      _applying = false;
    }
  }

  /// D19: this run only; nothing is stored, so the next start checks again.
  void _continue() {
    _timer?.cancel();
    bind.mainSetCommon(key: 'dolphin-update-continue', value: '');
    if (!widget.inApp) windowManager.setPreventClose(true);
    widget.openApp();
  }

  @override
  Widget build(BuildContext context) => DolphinUpdateView(
        check: _check,
        progress: _progress,
        currentVersion: DolphinBrand.version,
        framed: !widget.inApp,
        onRetry: _retry,
        onDownloadPage: () => launchUrl(Uri.parse(
            _check.downloadPage.isNotEmpty ? _check.downloadPage : '${DolphinBrand.portalUrl}/download')),
        onContinue: _continue,
        onClose: widget.onClose ?? () => windowManager.close(),
      );
}

/// DD-20: «بررسی نسخه‌ی تازه» in About (customer and technician apps). Asks the portal through the same Rust check
/// as the start-up (TB-20) and opens the same update screen when a newer build exists.
class DolphinUpdateCheckButton extends StatefulWidget {
  const DolphinUpdateCheckButton({super.key});

  @override
  State<DolphinUpdateCheckButton> createState() => _DolphinUpdateCheckButtonState();
}

class _DolphinUpdateCheckButtonState extends State<DolphinUpdateCheckButton> {
  ManualUpdateCheck _result = const ManualUpdateCheck(UpdateCheckPhase.idle);

  Future<void> _check() async {
    setState(() => _result = const ManualUpdateCheck(UpdateCheckPhase.checking));
    // At most about 4 s (CHECK_TIMEOUT in src/dolphin_update.rs); no answer reads as "unreachable".
    final raw = await bind.mainGetCommon(key: 'dolphin-update-recheck');
    if (mounted) setState(() => _result = ManualUpdateCheck.fromJson(raw));
  }

  Future<void> _update() async {
    final check = _result.screen;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        void close() => Navigator.of(ctx).pop();
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: DolphinUpdateScreen(
                  check: check, inApp: true, onClose: close, openApp: () async => close()),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) =>
      DolphinUpdateCheckView(phase: _result.phase, version: _result.version, onCheck: _check, onUpdate: _update);
}

/// Plan 19: the technician app's start-up popup, once per start. «به‌روزرسانی» runs [onUpdate] (the native app
/// downloads the build through the app API and installs it, tech_ui/technician_app.dart); without one, or when it
/// returns false (not signed in), it opens where the technician file is (the panel's «حساب من», staff sign-in, D13).
/// «بعداً» closes it and nothing is stored, so the next start asks again.
Future<void> showPendingTechUpdate(BuildContext context,
    {Future<bool> Function(BuildContext context, DolphinUpdateCheck check)? onUpdate}) async {
  final check = dolphinPendingTechUpdate;
  dolphinPendingTechUpdate = null;
  if (check == null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      void close() => Navigator.of(ctx).pop();
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        child: DolphinTechTheme(
          paint: false,
          child: DolphinTechUpdatePopupView(
            check: check,
            currentVersion: DolphinBrand.version,
            onUpdate: () async {
              close();
              if (onUpdate != null && context.mounted && await onUpdate(context, check)) return;
              launchUrl(Uri.parse(check.downloadPage.isNotEmpty ? check.downloadPage : '${DolphinBrand.portalUrl}/staff/me'));
            },
            onLater: close,
          ),
        ),
      );
    },
  );
}
