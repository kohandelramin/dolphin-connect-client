import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'brand.dart';
import 'theme.dart';
import 'update_view.dart';

const kDolphinUpdateSize = Size(480, 380);

/// TB-20: runs before the main window opens. True when the update screen took the window (the app stays closed).
///
/// [openApp] opens the normal home page; it runs when the customer taps «ادامه با همین نسخه» after a failure (D19).
Future<bool> runDolphinUpdateIfNeeded(Future<void> Function() openApp) async {
  if (!isWindows) return false; // the update screen is a Windows desktop screen
  final check = DolphinUpdateCheck.fromJson(await bind.mainGetCommon(key: 'dolphin-update-check'));
  if (!check.blocksStart) return false;
  await windowManager.setPreventClose(false);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: DolphinBrand.nameFa,
    theme: dolphinTheme(ThemeData.light()),
    home: Scaffold(body: DolphinUpdateScreen(check: check, openApp: openApp)),
  ));
  await windowManager.waitUntilReadyToShow(
      const WindowOptions(size: kDolphinUpdateSize, center: true, title: DolphinBrand.nameFa), () async {
    await windowManager.setOpacity(1);
    await windowManager.show();
    await windowManager.focus();
  });
  return true;
}

class DolphinUpdateScreen extends StatefulWidget {
  final DolphinUpdateCheck check;
  final Future<void> Function() openApp;
  const DolphinUpdateScreen({super.key, required this.check, required this.openApp});

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
    windowManager.setPreventClose(true);
    widget.openApp();
  }

  @override
  Widget build(BuildContext context) => DolphinUpdateView(
        check: _check,
        progress: _progress,
        onRetry: _retry,
        onDownloadPage: () => launchUrl(Uri.parse(
            _check.downloadPage.isNotEmpty ? _check.downloadPage : '${DolphinBrand.portalUrl}/download')),
        onContinue: _continue,
        onClose: () => windowManager.close(),
      );
}
