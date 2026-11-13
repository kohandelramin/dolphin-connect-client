import 'package:flutter/material.dart';

import 'switches.dart';
import 'theme.dart';

/// DD-41: upstream RustDesk's remote printer, behind the portal's `remote-printer` switch (owner 2026-11-13: hidden,
/// that is off, unless an organization turns it on). The customer prints to «<app> Printer», a virtual printer
/// whose driver ships with the customer app (drivers\RustDeskPrinterDriver, `.github/workflows/dolphin-build.yml`);
/// the job travels over the session's own file-transfer messages and the technician's app prints it with Windows'
/// spooler. Nothing about the connection changes: no codec, route or quality setting is touched.
///
///   hidden     no printer UI anywhere, an install leaves the virtual printer out (and removes an old one), and the
///              customer PC refuses every print job (src/dolphin_system_core.rs printer_forward);
///   available  the section shows; the customer installs the printer and switches printing to the technician on/off
///              (upstream's `enable-remote-printer`, on by default);
///   forced     printing is on and has no off switch; an install includes the virtual printer.
const kPrinterTitle = 'چاپگر راه دور';
const kPrinterOsText = 'چاپ از راه دور به ویندوز ۱۰ یا تازه‌تر نیاز دارد.';
const kPrinterNeedsInstallText = 'برای چاپ از راه دور، اول دلفین کانکت را روی این رایانه نصب کنید.';
const kPrinterInstallLabel = 'نصب چاپگر';
const kPrinterInstallingText = 'در حال نصب چاپگر… ویندوز اجازه‌ی مدیر را می‌پرسد.';
const kPrinterAllowLabel = 'چاپ روی چاپگر کارشناس';
const kPrinterForcedText = 'دلفین چاپ از راه دور را برای سازمان شما روشن کرده است.';

String printerMissingText(String printer) => 'چاپگر «$printer» هنوز روی این رایانه نصب نشده است.';
String printerReadyText(String printer) =>
    'چاپگر «$printer» آماده است. هنگام چاپ آن را انتخاب کنید تا برگه روی چاپگر کارشناس دلفین چاپ شود.';

enum PrinterUi { hidden, osTooOld, needsInstall, printerMissing, ready }

/// What the customer's About shows. The virtual printer needs Windows 10 and an installed app (upstream's own rules).
PrinterUi printerUi(
    {required SwitchMode mode, required bool windows10, required bool installed, required bool printerInstalled}) {
  if (mode == SwitchMode.hidden) return PrinterUi.hidden;
  if (!windows10) return PrinterUi.osTooOld;
  if (!installed) return PrinterUi.needsInstall;
  return printerInstalled ? PrinterUi.ready : PrinterUi.printerMissing;
}

/// Whether an install includes the virtual printer: never while hidden, always when forced, else upstream's choice
/// (`PRINTER` from the last install, off on a first install).
bool installWithPrinter(SwitchMode mode, bool chosen) => switch (mode) {
      SwitchMode.hidden => false,
      SwitchMode.forced => true,
      SwitchMode.available => chosen,
    };

/// Whether printing to the technician is on, as the section shows it (forced has no off switch).
bool printingOn(SwitchMode mode, String enableOption) => switch (mode) {
      SwitchMode.hidden => false,
      SwitchMode.forced => true,
      SwitchMode.available => enableOption != 'N',
    };

/// The section in the customer's About. Pure: everything comes in as values.
class DolphinPrinterCard extends StatelessWidget {
  final PrinterUi ui;
  final SwitchMode mode;

  /// «<app> Printer», the name the customer picks in a print dialog.
  final String printerName;
  final bool on;
  final bool installing;
  final String error;
  final VoidCallback onInstall;
  final ValueChanged<bool> onChanged;

  const DolphinPrinterCard(
      {super.key,
      required this.ui,
      required this.mode,
      required this.printerName,
      required this.on,
      required this.onInstall,
      required this.onChanged,
      this.installing = false,
      this.error = ''});

  @override
  Widget build(BuildContext context) {
    if (ui == PrinterUi.hidden) return const SizedBox.shrink();
    final body = TextStyle(color: DolphinColors.muted, height: 1.7);
    final children = <Widget>[
      Row(children: [
        Icon(Icons.print_outlined, size: 20, color: DolphinColors.azureText),
        SizedBox(width: 8),
        Text(kPrinterTitle, style: TextStyle(fontWeight: FontWeight.w700, color: DolphinColors.ink)),
      ]),
      const SizedBox(height: 6),
    ];
    switch (ui) {
      case PrinterUi.hidden:
        break;
      case PrinterUi.osTooOld:
        children.add(Text(kPrinterOsText, style: body));
      case PrinterUi.needsInstall:
        children.add(Text(kPrinterNeedsInstallText, style: body));
      case PrinterUi.printerMissing:
        children.addAll([
          Text(printerMissingText(printerName), style: body),
          const SizedBox(height: 8),
          if (installing)
            Text(kPrinterInstallingText, style: body)
          else
            FilledButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.add, size: 18),
                label: const Text(kPrinterInstallLabel, style: TextStyle(fontWeight: FontWeight.w700))),
        ]);
      case PrinterUi.ready:
        children.add(Text(printerReadyText(printerName), style: body));
    }
    if (error.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 6),
        Text(error, style: TextStyle(color: DolphinColors.dangerText, height: 1.6)),
      ]);
    }
    if (ui == PrinterUi.ready || ui == PrinterUi.printerMissing) {
      children.add(const SizedBox(height: 4));
      children.add(mode == SwitchMode.forced
          ? Text(kPrinterForcedText, style: TextStyle(color: DolphinColors.aquaText, height: 1.7))
          : SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(kPrinterAllowLabel, style: TextStyle(color: DolphinColors.ink)),
              value: on,
              onChanged: onChanged,
            ));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: DolphinColors.line),
          borderRadius: BorderRadius.circular(DolphinRadii.control),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
