import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(
          textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  test('server status maps to the three states', () {
    expect(serverStateFromStatus(1), DolphinServerState.ready);
    expect(serverStateFromStatus(0), DolphinServerState.connecting);
    expect(serverStateFromStatus(-1), DolphinServerState.offline);
  });

  test('IDs are grouped in threes for reading aloud', () {
    expect(groupId('123456789'), '123 456 789');
    expect(groupId('1234567890'), '1 234 567 890');
    expect(groupId('abc-12'), 'abc-12');
  });

  test('support numbers pushed by the portal win over the compiled one', () {
    expect(supportPhone('021-44200250 · 0912-0000000', '021-44200250'), '021-44200250 · 0912-0000000');
    expect(supportPhone('  ', '021-44200250'), '021-44200250');
  });

  test('the theme uses Vazirmatn and azure', () {
    final t = dolphinTheme(ThemeData.light());
    expect(t.textTheme.bodyMedium?.fontFamily, kDolphinFont);
    expect(t.colorScheme.primary, DolphinColors.azure);
  });

  testWidgets('home shows the grouped ID, status and footer; copy works',
      (tester) async {
    var copied = false;
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.ready,
        onCopy: () => copied = true,
        phone: '021-12345678',
        siteLabel: 'support.dolphindev.ir')));
    expect(find.text('123 456 789'), findsOneWidget);
    expect(find.textContaining('آماده'), findsOneWidget);
    expect(find.textContaining('021-12345678'), findsOneWidget);
    await tester.tap(find.text('کپی شناسه'));
    expect(copied, isTrue);
  });

  testWidgets('home says when the server is unreachable', (tester) async {
    await tester.pumpWidget(_app(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.offline,
        onCopy: () {},
        phone: '',
        siteLabel: 'support.dolphindev.ir')));
    expect(find.textContaining('وصل نیست'), findsOneWidget);
  });

  testWidgets('accept prompt: file transfer off by default, accept passes the toggles',
      (tester) async {
    List<bool>? got;
    var denied = false;
    await tester.pumpWidget(_app(DolphinAcceptView(
        technician: 'علی رضایی',
        onAccept: (k, c, f) => got = [k, c, f],
        onDeny: () => denied = true)));
    expect(find.textContaining('علی رضایی'), findsOneWidget);
    await tester.tap(find.text('پذیرفتن'));
    expect(got, [true, true, false]);
    await tester.tap(find.text('رد'));
    expect(denied, isTrue);
  });

  testWidgets('session view shows the technician, time and End', (tester) async {
    var ended = false;
    await tester.pumpWidget(_app(DolphinSessionView(
        technician: 'علی رضایی',
        elapsed: const Duration(minutes: 4, seconds: 12),
        fileEnabled: false,
        onFile: (_) {},
        onEnd: () => ended = true)));
    expect(find.text('04:12'), findsOneWidget);
    await tester.tap(find.text('پایان'));
    expect(ended, isTrue);
  });
}
