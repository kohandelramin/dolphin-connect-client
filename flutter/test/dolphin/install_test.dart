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
}
