import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/install_view.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: dolphinTheme(ThemeData.light()), home: Scaffold(body: child));

void main() {
  testWidgets('the installer is one button, then progress; no options, no licence link', (tester) async {
    var installs = 0;
    await tester.pumpWidget(_app(DolphinInstallView(onInstall: () => installs++)));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('قرارداد'), findsNothing);
    expect(find.textContaining('بدون نصب'), findsNothing);
    expect(Directionality.of(tester.element(find.text('نصب'))), TextDirection.rtl);
    await tester.tap(find.text('نصب'));
    await tester.pump();
    expect(installs, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('نصب'), findsNothing);
  });

  testWidgets('run without install is offered when upstream offers it', (tester) async {
    var ran = false;
    await tester.pumpWidget(_app(DolphinInstallView(onInstall: () {}, onRunWithoutInstall: () => ran = true)));
    await tester.tap(find.textContaining('بدون نصب'));
    expect(ran, isTrue);
  });

  testWidgets('after 60 s of installing the button comes back with a hint; the timer ends with the view', (tester) async {
    var installs = 0;
    await tester.pumpWidget(_app(DolphinInstallView(onInstall: () => installs++)));
    await tester.tap(find.text('نصب'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('نصب'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('«نه» زدید'), findsOneWidget);
    await tester.tap(find.text('نصب'));
    await tester.pump();
    expect(installs, 2);
    expect(find.text('نصب'), findsNothing); // progress again, hint gone
    // Leaving the view cancels the timer: no pending timer is left (the test would fail).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('run without install runs once', (tester) async {
    var ran = 0;
    await tester.pumpWidget(_app(DolphinInstallView(onInstall: () {}, onRunWithoutInstall: () => ran++)));
    await tester.tap(find.textContaining('بدون نصب'));
    await tester.pump();
    await tester.tap(find.textContaining('بدون نصب'), warnIfMissed: false);
    await tester.pump();
    expect(ran, 1);
  });

  testWidgets('the body promises shortcuts only when the options are known to be on', (tester) async {
    await tester.pumpWidget(_app(DolphinInstallView(onInstall: () {})));
    expect(find.textContaining('Start'), findsNothing);
    expect(find.textContaining('برنامه در رایانه‌ی شما نصب می‌شود.'), findsOneWidget);
    await tester.pumpWidget(_app(DolphinInstallView(onInstall: () {}, shortcutsOn: true)));
    expect(find.textContaining('Start'), findsOneWidget);
  });
}
