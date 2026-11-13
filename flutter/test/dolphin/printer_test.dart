import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/printer.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: dolphinTheme(ThemeData.light()), home: Scaffold(body: child));

const _name = 'DolphinConnect Printer';

void main() {
  group('the rules (DD-41)', () {
    test('off by default: the portal has to turn it on', () {
      expect(DolphinSwitches.parse('').mode(DolphinSwitch.remotePrinter), SwitchMode.hidden);
      expect(DolphinSwitches.parse('{"remote-printer":"available"}').mode(DolphinSwitch.remotePrinter),
          SwitchMode.available);
    });

    test('what the section shows', () {
      PrinterUi ui(SwitchMode m, {bool w10 = true, bool installed = true, bool printer = false}) =>
          printerUi(mode: m, windows10: w10, installed: installed, printerInstalled: printer);
      expect(ui(SwitchMode.hidden, printer: true), PrinterUi.hidden);
      expect(ui(SwitchMode.available, w10: false), PrinterUi.osTooOld);
      expect(ui(SwitchMode.forced, installed: false), PrinterUi.needsInstall);
      expect(ui(SwitchMode.available), PrinterUi.printerMissing);
      expect(ui(SwitchMode.forced, printer: true), PrinterUi.ready);
    });

    test('an install takes the virtual printer only when the portal allows it', () {
      expect(installWithPrinter(SwitchMode.hidden, true), isFalse, reason: 'hidden removes an old one too');
      expect(installWithPrinter(SwitchMode.forced, false), isTrue);
      expect(installWithPrinter(SwitchMode.available, true), isTrue);
      expect(installWithPrinter(SwitchMode.available, false), isFalse);
    });

    test('printing to the technician: forced has no off, available follows the option (on unless "N")', () {
      expect(printingOn(SwitchMode.hidden, 'Y'), isFalse);
      expect(printingOn(SwitchMode.forced, 'N'), isTrue);
      expect(printingOn(SwitchMode.available, ''), isTrue);
      expect(printingOn(SwitchMode.available, 'N'), isFalse);
    });
  });

  group('the card', () {
    Future<List<Object>> pump(WidgetTester tester, PrinterUi ui, SwitchMode mode,
        {bool on = true, bool installing = false, String error = ''}) async {
      final calls = <Object>[];
      await tester.pumpWidget(_app(DolphinPrinterCard(
          ui: ui,
          mode: mode,
          printerName: _name,
          on: on,
          installing: installing,
          error: error,
          onInstall: () => calls.add('install'),
          onChanged: (v) => calls.add(v))));
      return calls;
    }

    testWidgets('hidden draws nothing', (tester) async {
      await pump(tester, PrinterUi.hidden, SwitchMode.hidden);
      expect(find.text(kPrinterTitle), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('a missing printer offers «نصب چاپگر» and the customer\'s switch', (tester) async {
      final calls = await pump(tester, PrinterUi.printerMissing, SwitchMode.available);
      expect(find.text(printerMissingText(_name)), findsOneWidget);
      await tester.tap(find.text(kPrinterInstallLabel));
      await tester.tap(find.byType(Switch));
      expect(calls, ['install', false]);
    });

    testWidgets('while installing there is no second button', (tester) async {
      await pump(tester, PrinterUi.printerMissing, SwitchMode.available, installing: true);
      expect(find.text(kPrinterInstallingText), findsOneWidget);
      expect(find.text(kPrinterInstallLabel), findsNothing);
    });

    testWidgets('ready says which printer to pick; forced has no off switch', (tester) async {
      await pump(tester, PrinterUi.ready, SwitchMode.forced, error: 'نصب چاپگر انجام نشد: x');
      expect(find.text(printerReadyText(_name)), findsOneWidget);
      expect(find.text(kPrinterForcedText), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('نصب چاپگر انجام نشد: x'), findsOneWidget);
    });

    testWidgets('an old Windows or a portable run only explains', (tester) async {
      await pump(tester, PrinterUi.osTooOld, SwitchMode.available);
      expect(find.text(kPrinterOsText), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      await pump(tester, PrinterUi.needsInstall, SwitchMode.forced);
      expect(find.text(kPrinterNeedsInstallText), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });
}
