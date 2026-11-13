import 'package:flutter/material.dart';

import '../common.dart' show appName;
import '../models/platform_model.dart';
import 'printer.dart';
import 'switches.dart';

/// DD-41: the `remote-printer` switch as the portal last pushed it (hidden until the first heartbeat says otherwise).
SwitchMode dolphinPrinterMode() =>
    DolphinSwitches.parse(bind.mainGetOptionSync(key: kDolphinSwitchesOption)).mode(DolphinSwitch.remotePrinter);

/// Upstream's «Printer» settings tab (technician: what to do with incoming jobs) follows the switch. The tab list is
/// read once per window, so a change shows after the app opens again.
bool dolphinPrinterTabShown() => dolphinPrinterMode() != SwitchMode.hidden;

/// The installer's printer option (src/platform/windows.rs install_me: `printer` installs the virtual printer, its
/// absence removes it on Windows 10 and later).
bool dolphinInstallWithPrinter(bool chosen) => installWithPrinter(dolphinPrinterMode(), chosen);

const _kEnableRemotePrinter = 'enable-remote-printer';

/// The customer's About section: install the virtual printer, switch printing to the technician on or off. Reads and
/// writes only upstream's own keys (`is-printer-installed`, `install-printer`, `enable-remote-printer`).
class DolphinPrinterSection extends StatefulWidget {
  const DolphinPrinterSection({super.key});

  @override
  State<DolphinPrinterSection> createState() => _DolphinPrinterSectionState();
}

class _DolphinPrinterSectionState extends State<DolphinPrinterSection> {
  bool _installing = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    platformFFI.registerEventHandler('install-printer-res', 'dolphin-install-printer-res', (evt) async {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = evt['success'] == true ? '' : 'نصب چاپگر انجام نشد: ${evt['msg'] ?? ''}';
      });
    }, replace: true);
  }

  @override
  void dispose() {
    platformFFI.unregisterEventHandler('install-printer-res', 'dolphin-install-printer-res');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = dolphinPrinterMode();
    final ui = printerUi(
      mode: mode,
      windows10: bind.mainGetCommonSync(key: 'is-support-printer-driver') == 'true',
      installed: bind.mainIsInstalled(),
      printerInstalled: bind.mainGetCommonSync(key: 'is-printer-installed') == 'true',
    );
    return DolphinPrinterCard(
      ui: ui,
      mode: mode,
      printerName: '$appName Printer',
      on: printingOn(mode, bind.mainGetOptionSync(key: _kEnableRemotePrinter)),
      installing: _installing,
      error: _error,
      onInstall: () {
        setState(() {
          _installing = true;
          _error = '';
        });
        bind.mainSetCommon(key: 'install-printer', value: '');
      },
      onChanged: (v) async {
        await bind.mainSetOption(key: _kEnableRemotePrinter, value: v ? 'Y' : 'N');
        if (mounted) setState(() {});
      },
    );
  }
}
