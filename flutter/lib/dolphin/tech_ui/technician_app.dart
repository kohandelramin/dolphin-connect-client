import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../demo_hooks.dart' show startDemo;
import '../tech/launcher.dart';
import '../tech/services.dart';
import '../tech_theme.dart';
import '../theme.dart' show dolphinRebuildOnThemeChange;
import '../update.dart';
import '../update_view.dart' show DolphinUpdateCheck;
import 'app_platform.dart';
import 'shell.dart';
import 'shell_model.dart';
import 'updater.dart';
import 'updater_view.dart';
import 'widgets.dart';

/// Plan 19: the technician build's main window, fully native (T1–T7). It replaces DolphinTechnicianHome (the staff
/// panel in WebView2): the data layer opens once (DPAPI-sealed sign-in, offline list), then [TechShell] draws the
/// sign-in or the window. Hook: flutter/lib/desktop/pages/desktop_home_page.dart.
class DolphinTechnicianApp extends StatefulWidget {
  const DolphinTechnicianApp({super.key});

  @override
  State<DolphinTechnicianApp> createState() => _DolphinTechnicianAppState();
}

class _DolphinTechnicianAppState extends State<DolphinTechnicianApp> {
  final _platform = AppTechPlatform();
  TechServices? _services;
  TechShellModel? _model;
  String? _error;

  @override
  void initState() {
    super.initState();
    dolphinRebuildOnThemeChange();
    applyTechWindowSize();
    _open();
    // Plan 19: a newer technician build found at this start: «به‌روزرسانی» / «بعداً» over the open app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showPendingTechUpdate(context, onUpdate: _update);
    });
  }

  Future<void> _open() async {
    try {
      // «ارائه دمو»: after the portal's authorization, demo_hooks.dart opens the demo session (D1–D2).
      final s = await TechServices.open(
          launcher: RustdeskSessionLauncher(),
          prefs: const LocalOptionPrefs(),
          demoStarter: TechDemoStarter((id, all) => startDemo(id, allScreens: all)));
      await s.session.load();
      if (!mounted) {
        s.dispose();
        return;
      }
      setState(() {
        _services = s;
        _model = TechShellModel(s, _platform);
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'برنامه‌ی کارشناس باز نشد؛ آن را ببندید و دوباره باز کنید.');
    }
  }

  /// «به‌روزرسانی»: through the app API when signed in; false sends the technician to the portal's page instead.
  Future<bool> _update(BuildContext context, DolphinUpdateCheck check) async {
    final model = _model;
    if (model == null || !model.services.session.signedIn) return false;
    final latest = model.config.value?.latest ?? (await model.config.load())?.latest;
    if (latest == null || !context.mounted) return false;
    final updater = TechUpdater(model.services.api, const AppUpdateInstaller(),
        sessionsOpen: () => model.platform.sessions.open.isNotEmpty);
    updater.run(latest);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: DolphinTechTheme(
          paint: false,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: TechUpdateProgressView(
              updater: updater,
              version: latest.version,
              onRetry: () => updater.run(latest),
              onDownloadPage: () => launchUrl(Uri.parse(
                  check.downloadPage.isNotEmpty ? check.downloadPage : '${DolphinBrand.portalUrl}/staff/me')),
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
      ),
    );
    updater.dispose();
    return true;
  }

  @override
  void dispose() {
    _model?.dispose();
    _services?.dispose();
    _platform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = _model;
    if (model == null) {
      return DolphinTechTheme(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: _error == null ? const TechLoading() : TechEmpty(icon: Icons.error_outline, text: _error!),
        ),
      );
    }
    return TechShell(model: model, updateButton: const DolphinUpdateCheckButton());
  }
}
