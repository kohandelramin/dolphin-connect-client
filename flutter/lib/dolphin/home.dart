import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;

import '../common.dart';
import '../consts.dart';
import '../common/formatter/id_formatter.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'about.dart';
import 'brand.dart';
import 'callback.dart';
import 'customer_requests.dart';
import 'customer_settings.dart';
import 'digits.dart';
import 'first_run_view.dart';
import 'health.dart';
import 'health_probe.dart';
import 'home_helpers.dart';
import 'home_status.dart';
import 'home_view.dart';
import 'log_files.dart';
import 'network_status.dart';
import 'panel_bridge.dart';
import 'recent_sessions.dart';
import 'safe_mode_hooks.dart';
import 'screenshot.dart';
import 'share.dart';
import 'support_upload.dart';
import 'support_views.dart';
import 'switches.dart';
import 'tech_card.dart';
import 'theme_option.dart';
import 'verify.dart';
import 'window_sizes.dart';

/// Pushed by the portal with every heartbeat (app/src/lib/engine/policy.ts SUPPORT_PHONE_OPTION),
/// so admins change the numbers without a new release.
const kDolphinSupportPhoneOption = 'dolphin-support-phone';

/// Upstream sizes the incoming-only window as its content plus the title bar (common.dart getIncomingOnlyHomeSize);
/// the content that gives [window] (Plan 19 C1: 380 × 580, window_sizes.dart homeWindowSize).
Size homeContentSize(Size window) =>
    Size(window.width - (Platform.isWindows ? 11.0 : 2.0), window.height - kDesktopRemoteTabBarHeight - 10);

/// The screen's logical size (the first display), for the window sizes.
Size _screenSize() {
  final displays = WidgetsBinding.instance.platformDispatcher.displays;
  return displays.isEmpty ? kDolphinRequestsSize : displays.first.size / displays.first.devicePixelRatio;
}


/// Customer build's main window: the ID screen, or the request section (the customer portal).
class DolphinHome extends StatefulWidget {
  const DolphinHome({super.key});

  @override
  State<DolphinHome> createState() => _DolphinHomeState();
}

class _DolphinHomeState extends State<DolphinHome> {
  bool _requests = false;
  Timer? _options;
  // Authorised remote sessions, from the server (see connectedCount). Null until the first read: no code before that.
  int? _connected;
  // BL-SVC: the service was stopped (tray «توقف سرویس» before 2.0.0-rc.5, or an uninstall); the home then says so.
  bool _stopped = false;
  // DD-17: the first-run screen, until «بعدی» was pressed once (a local option).
  bool _firstRun = false;
  // DD-32: the ID differs from the one this app saw last; shown until closed.
  bool _idChanged = false;
  // DD-19: the installed app's Windows service, read every 10 s (two reads in a row before the notice shows).
  final _serviceWatch = ServiceWatch();
  int _ticks = 0;
  // DD-40: what to do on a PC with no monitor; '' when it has one.
  String _headlessFix = '';

  @override
  void initState() {
    super.initState();
    // Plan 19 C5: the customer's own light or dark, before the first frame.
    applyCustomerThemeChoice();
    // Upstream sizes the incoming-only window from its own home page, which this build does not show.
    imcomingOnlyHomeSize = homeContentSize(homeWindowSize(_screenSize()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitWindow());
    // Options the portal pushes (support phone, whether to show the code) change without the server model noticing.
    // No immediate read: the count reaches the app about 1 s after the status sync starts, and an early read would be
    // the unsynced 0 (the code would flash during a session). The first read is the 2 s tick; until then it is unknown
    // and the code stays hidden (codeHiddenFor(null)).
    _options = Timer.periodic(const Duration(seconds: 2), (_) => _readConnected());
    // Plan 19: the portal's theme (`dolphin-theme`), then on every 2 s read when it changes.
    syncThemeFromPortal();
    _readStopped();
    _firstRun = firstRunShown(bind.mainGetLocalOption(key: kDolphinFirstRunLocal));
    // Plan 18 Phase 4: DD-39 log cleanup (at most once a day), DD-40 the monitor check, DD-19 the first service read.
    _cleanLogs();
    _readHeadless();
    _readService();
  }

  @override
  void dispose() {
    _options?.cancel();
    super.dispose();
  }

  Future<void> _readConnected() async {
    final n = connectedCount(await bind.mainGetConnectStatus());
    syncThemeFromPortal();
    final stopped = await mainGetBoolOption(kOptionStopService);
    if (++_ticks % 5 == 0) _readService();
    final changed = _noteId(trimID(gFFI.serverModel.serverId.text));
    if (mounted) {
      setState(() {
        _connected = n;
        _stopped = stopped || _serviceWatch.down;
        if (changed) _idChanged = true;
      });
    }
  }

  /// DD-32: compare the ID shown with the last one stored on this Windows account; true when it changed.
  bool _noteId(String id) {
    final seen = idSeen(stored: bind.mainGetLocalOption(key: kDolphinSeenIdLocal), current: id);
    final store = seen.store;
    if (store != null) bind.mainSetLocalOption(key: kDolphinSeenIdLocal, value: store);
    return seen.changed;
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast('کپی شد');
  }

  void _endFirstRun() {
    bind.mainSetLocalOption(key: kDolphinFirstRunLocal, value: 'Y');
    setState(() => _firstRun = false);
  }

  Future<void> _readStopped() async {
    final stopped = await mainGetBoolOption(kOptionStopService);
    if (mounted) setState(() => _stopped = stopped || _serviceWatch.down);
  }

  // ---- Plan 18 Phase 4: health, reports, screenshot (DD-7, DD-19, DD-38, DD-39, DD-40, DD-48) ----

  String get _appName => bind.mainGetAppNameSync();
  String get _appData => Platform.environment['APPDATA'] ?? '';
  String get _logDir => logDirFor(appData: _appData, appName: _appName);
  String get _ownId => trimID(gFFI.serverModel.serverId.text);

  /// DD-19: the Windows service of an installed app; the red notice with «درست کن» after two "down" reads in a row.
  void _readService() {
    if (!Platform.isWindows) return;
    final installed = bind.mainIsInstalled();
    final stopOption = mainGetBoolOptionSync(kOptionStopService);
    final down = serviceDown(installed: installed, state: readServiceState(_appName), stopOption: stopOption);
    if (_serviceWatch.note(down) && mounted) setState(() => _stopped = stopOption || _serviceWatch.down);
  }

  /// DD-39: logs older than 7 days into one scrubbed backup zip, at most once a day.
  Future<void> _cleanLogs() async {
    if (!Platform.isWindows || _appData.isEmpty) return;
    final now = DateTime.now();
    if (!cleanupDue(bind.mainGetLocalOption(key: kDolphinLogsCleanedLocal), now)) return;
    bind.mainSetLocalOption(key: kDolphinLogsCleanedLocal, value: cleanupStamp(now));
    try {
      await cleanLogsAsync(_logDir, now, ownId: _ownId);
    } catch (_) {}
  }

  /// DD-40: one small screen, or none, is Windows' stand-in for a PC with no monitor.
  Future<void> _readHeadless() async {
    if (!Platform.isWindows) return;
    try {
      final screens = await window_size.getScreenList();
      // rcMonitor: physical pixels, as the app is per-monitor DPI aware.
      final headless = looksHeadless([for (final s in screens) (s.frame.width, s.frame.height)]);
      final fix = headless ? headlessFix(installed: bind.mainIsInstalled(), windowsBuild: windowsBuildNumber) : '';
      if (mounted && fix != _headlessFix) setState(() => _headlessFix = fix);
    } catch (_) {}
  }

  bool get _uploadShown => uploadShown(
      DolphinSwitches.parse(bind.mainGetOptionSync(key: kDolphinSwitchesOption)).mode(DolphinSwitch.diagnosticsUpload));

  HealthInputs _healthInputs() => HealthInputs(
        installed: bind.mainIsInstalled(),
        serviceName: _appName,
        stopOption: mainGetBoolOptionSync(kOptionStopService),
        registered: gFFI.serverModel.connectStatus > 0,
        rendezvous: bind.mainGetOptionSync(key: kRendezvousServerOption),
        relay: bind.mainGetOptionSync(key: 'relay-server'),
        portal: DolphinBrand.portalUrl,
        appDirs: _appData.isEmpty ? const [] : ['$_appData\\$_appName\\config', _logDir],
        headless: _headlessFix.isNotEmpty,
        windowsBuild: windowsBuildNumber,
      );

  /// DD-7 and DD-38: the short text, with the checks just run (the service line first). Only this PC's own facts.
  String _diagnostic(List<HealthItem> checks) {
    final state = serverStateFromStatus(gFFI.serverModel.connectStatus, serviceStopped: _stopped);
    return diagnosticText(DiagnosticFacts(
      appVersion: DolphinBrand.version,
      windows: Platform.operatingSystemVersion,
      installed: bind.mainIsInstalled(),
      service: checks.isEmpty ? '' : checks.first.result,
      network: diagnosticNetworkRows(
        server: state,
        serverAddress: bind.mainGetOptionSync(key: kRendezvousServerOption),
        localIp: bind.mainGetOptionSync(key: kLocalIpOption),
        idChanged: _idChanged,
      ).map((r) => r.toString()).toList(),
      checks: checks.map((c) => c.line).toList(),
      ownId: _ownId,
      at: DateTime.now(),
    ));
  }

  /// The one safe repair: upstream's own start. An installed app recreates and starts the service behind a UAC
  /// prompt, then reopens the window.
  void _fix(HealthFix fix) {
    if (fix == HealthFix.startService) start_service(true);
  }

  Future<String> _saveHealth(List<HealthItem> items) async {
    final name = healthReportName(DateTime.now());
    try {
      await File('${desktopDir()}\\$name').writeAsString(_diagnostic(items), flush: true);
      return 'گزارش روی دسکتاپ ذخیره شد:\n$name';
    } catch (_) {
      return 'گزارش ذخیره نشد؛ جای خالی دیسک را بررسی کنید.';
    }
  }

  void _openHealth() => showDolphinPanel(
      context,
      (close) => DolphinHealthDialog(
            run: () => runHealthChecks(_healthInputs()),
            onFix: (fix) {
              close();
              _fix(fix);
            },
            onSave: _saveHealth,
            onClose: close,
          ));

  Future<UploadAnswer> _post(UploadKind kind, Uint8List bytes, String note) async {
    final id = await bind.mainGetMyId();
    final uuid = await bind.mainGetUuid();
    return postUpload(uploadUri(DolphinBrand.portalUrl, kind, id: id, uuid: uuid, note: note), bytes, kind);
  }

  /// DD-7: the zip is built when «فرستادن» is pressed: the checks, the recent logs and DD-39's newest backup.
  Future<UploadAnswer> _sendReport(String note) async {
    final text = _diagnostic(await runHealthChecks(_healthInputs()));
    final dir = _logDir;
    final files = listLogFolder(Directory(dir));
    final zip = await buildReportZipAsync(
        diagnostic: text, logRoot: dir, logs: reportLogs(files, DateTime.now()), backup: newestBackup(files), ownId: _ownId);
    return _post(UploadKind.diagnostics, zip, note);
  }

  void _openReport() => showDolphinPanel(
      context, (close) => DolphinUploadForm(kind: UploadKind.diagnostics, onSend: _sendReport, onClose: close));

  /// DD-48: our window steps aside, the screen is read, and the window comes back with the picture to look at before
  /// anything is sent.
  Future<void> _takeScreenshot() async {
    RawScreen? raw;
    try {
      await windowManager.minimize();
      await Future.delayed(const Duration(milliseconds: 700));
      raw = captureScreen();
    } catch (_) {
    } finally {
      await windowManager.restore();
      await windowManager.show();
    }
    final png = raw == null ? null : await encodeScreen(raw);
    if (!mounted) return;
    if (png == null) {
      showToast('عکس صفحه گرفته نشد.');
      return;
    }
    showDolphinPanel(
        context,
        (close) => DolphinUploadForm(
            kind: UploadKind.screenshot, png: png, onSend: (note) => _post(UploadKind.screenshot, png, note), onClose: close));
  }

  Future<void> _fitWindow() async {
    if (_requests) {
      setResizable(true);
      // UX-18: fit the screen (a 1366 × 768 laptop cannot take 980 × 720 plus the title bar).
      await windowManager.setSize(requestsSize(_screenSize()));
      await windowManager.center();
    } else {
      // Plan 19 C1: 380 × 580, smaller only on a screen that cannot hold it (never under 360 × 540).
      imcomingOnlyHomeSize = homeContentSize(homeWindowSize(_screenSize()));
      await windowManager.setSize(getIncomingOnlyHomeSize());
      setResizable(false);
    }
  }

  /// Plan 14 (B6): src/dolphin_callback.rs sends in the background; ask for its state until it has an answer.
  Future<CallbackStatus> _sendCallback(String name, String phone, String note) async {
    await bind.mainSetCommon(key: 'dolphin-callback-send', value: jsonEncode({'name': name, 'phone': phone, 'note': note}));
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final status = CallbackStatus.fromJson(await bind.mainGetCommon(key: 'dolphin-callback-state'));
      if (status.phase == CallbackPhase.done || status.phase == CallbackPhase.failed) return status;
    }
    return const CallbackStatus(CallbackPhase.failed, 'پاسخی نیامد؛ با پشتیبانی دلفین تماس بگیرید.');
  }

  void _openCallback() => showDolphinCallback(context, _sendCallback);

  /// Plan 14 (B5), DD-43: who the portal has authorized for this PC; the bar shows them on the way or connected.
  TechComing? _tech() {
    String opt(String key) => bind.mainGetOptionSync(key: key);
    return authorizedTech(
      techId: opt(kDolphinTechIdOption),
      techName: opt(kDolphinTechNameOption),
      until: int.tryParse(opt(kDolphinTechUntilOption)) ?? 0,
      nowSeconds: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      photo: opt(kDolphinTechPhotoOption),
    );
  }

  void _show(bool requests) {
    setState(() => _requests = requests);
    _fitWindow();
  }

  // DD-11: in Safe Mode, «حالت امن» with «بازگشت به حالت عادی» (safe_mode_hooks.dart; nothing on a normal boot).
  // DD-34 «اشتراک‌گذاری» is a switch inside the home since Plan 19 C1 (share.dart; nothing when the portal hides it).
  @override
  Widget build(BuildContext context) => Column(children: [
        if (!_requests) const DolphinSafeModeHome(),
        Expanded(child: _buildHome(context)),
      ]);

  Widget _buildHome(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        // serverId is declared as a TextEditingController but built as the ID controller (server_model.dart).
        final id = trimID(model.serverId.text);
        final code = dolphinCode(
            approveMode: model.approveMode,
            showCode: bind.mainGetOptionSync(key: kDolphinShowCodeOption),
            password: model.serverPasswd.text,
            inSession: codeHiddenFor(_connected));
        if (_requests) {
          return DolphinCustomerRequests(id: id, code: portalCode(model.approveMode, code), onBack: () => _show(false));
        }
        // DD-44: the clipboard always gets Latin digits.
        void copyId() => _copy(idForClipboard(id));
        if (_firstRun) return DolphinFirstRunView(id: id, onCopy: copyId, onNext: _endFirstRun);
        final state = serverStateFromStatus(model.connectStatus, serviceStopped: _stopped);
        final links = DolphinLinks(DolphinBrand.site);
        // DD-8: read from the synced options, like the portal's pushed ones; nothing here touches the network.
        final ip = localIpFrom(bind.mainGetOptionSync(key: kLocalIpOption));
        return DolphinHomeView(
          id: id,
          code: code,
          codeSpoken: codeSpoken(model.approveMode),
          onCopyCode: () => _copy(code),
          state: state,
          // Upstream's own action: clears `stop-service`, which on an installed app recreates and starts the Windows
          // service (UAC prompt); the 2 s read then shows the new state.
          onStartService: () => start_service(true),
          phone: supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone),
          siteLabel: DolphinBrand.siteLabel,
          onCopy: copyId,
          onRequests: () => _show(true),
          recent: parseRecentSessions(bind.mainGetOptionSync(key: kDolphinRecentSessionsOption)),
          coming: _tech(),
          connected: _connected,
          onCallback: callbackShown(bind.mainGetOptionSync(key: kDolphinCallbackOption)) ? _openCallback : null,
          // Owner 2026-11-13: the state and this PC's IP only; the ID change has its own notice below.
          network: networkRows(server: state, localIp: ip),
          idChanged: _idChanged,
          onDismissIdNotice: () => setState(() => _idChanged = false),
          onStartHere: () => launchUrl(Uri.parse(links.help)),
          onCopyIp: ip.isEmpty ? null : () => _copy(ip),
          onCopyDownload: () => _copy(links.download),
          onCopyGuide: () => _copy(links.guide),
          version: DolphinBrand.version,
          onHealth: isWindows ? _openHealth : null,
          onReport: isWindows && _uploadShown ? _openReport : null,
          onScreenshot: isWindows && _uploadShown ? _takeScreenshot : null,
          headlessFix: _headlessFix,
          onAbout: () => showDolphinAboutDialog(context), // DD-20
          share: const DolphinShareControl(), // DD-34
          onSettings: () => showDolphinCustomerSettings(context), // Plan 19 C5
        );
      }),
    );
  }
}
