import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/reconnect.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

Widget _session({bool? resumed}) => _app(resumed == null
    ? DolphinSessionView(
        technician: 'علی رضایی',
        elapsed: const Duration(minutes: 1),
        keyboard: true,
        clipboard: true,
        file: true,
        onToggle: (_, __) {},
        onEnd: () {})
    : DolphinSessionView(
        technician: 'علی رضایی',
        elapsed: const Duration(minutes: 1),
        keyboard: true,
        clipboard: true,
        file: true,
        resumed: resumed,
        onToggle: (_, __) {},
        onEnd: () {}));

void main() {
  final t0 = DateTime(2026, 11, 10, 10);

  bool retry(String text,
          {bool technician = true,
          bool wasConnected = true,
          String type = 'error',
          String title = 'Connection Error',
          DateTime? firstDrop,
          DateTime? now}) =>
      dolphinQuietRetry(
          technician: technician,
          wasConnected: wasConnected,
          type: type,
          title: title,
          text: text,
          firstDrop: firstDrop,
          now: now ?? t0);

  test('a dropped link is retried quietly, including the errors upstream gives up on', () {
    for (final text in ['Reset by the peer', 'Timeout', 'Remote desktop is offline', 'Failed to connect to relay server',
        'Failed to connect via rendezvous server', 'os error 10054', 'Connection reset without closing handshake',
        'Failed to resolve remote.dolphindev.ir']) {
      expect(retry(text), isTrue, reason: text);
    }
    expect(retry('os error 10054', type: 'relay-hint'), isTrue);
    expect(retry('os error 10054', type: 'relay-hint2'), isTrue);
  });

  test('an end on purpose or a security stop is never retried quietly', () {
    for (final text in ['Closed manually by the peer', 'Closed manually by web console', 'Connection not allowed',
        'Incoming only mode', 'Key mismatch', 'Wrong Password', 'No permission of file transfer',
        'Connection failed due to inactivity', 'ID does not exist', 'Too many wrong attempts']) {
      expect(retry(text), isFalse, reason: text);
    }
  });

  test('only the technician app, only after a session was up, only connection errors', () {
    expect(retry('Timeout', technician: false), isFalse);
    expect(retry('Timeout', wasConnected: false), isFalse);
    expect(retry('Timeout', title: 'Login Error'), isFalse);
    expect(retry('Timeout', type: 'info'), isFalse);
  });

  test('the window is two minutes from the first drop, not from each retry', () {
    expect(retry('Timeout', firstDrop: t0, now: t0.add(const Duration(seconds: 119))), isTrue);
    expect(retry('Timeout', firstDrop: t0, now: t0.add(const Duration(seconds: 120))), isFalse);
    expect(kDolphinReconnectWindow, const Duration(minutes: 2));
  });

  test('retries come quickly, then every 5 seconds', () {
    expect([for (var i = 0; i < 7; i++) dolphinRetryDelay(i).inSeconds], [1, 2, 3, 5, 5, 5, 5]);
    // about 24 tries fit in the window, never a 64 s wait
    var total = 0, tries = 0;
    while (total < kDolphinReconnectWindow.inSeconds) {
      total += dolphinRetryDelay(tries++).inSeconds;
    }
    expect(tries, greaterThan(20));
  });

  test('the text says what happens, in Persian digits', () {
    expect(dolphinReconnectingText(const Duration(seconds: 95)), contains('در حال اتصال دوباره…'));
    expect(dolphinReconnectingText(const Duration(seconds: 95)), contains('۹۵'));
    expect(dolphinReconnectingText(const Duration(seconds: -3)), contains('۰'));
    expect(kDolphinReconnected, 'دوباره وصل شد');
  });

  test('the customer window calls it a comeback only within two minutes of the last live session', () {
    expect(dolphinResumed(null, t0), isFalse);
    expect(dolphinResumed(t0, t0.add(const Duration(seconds: 119))), isTrue);
    expect(dolphinResumed(t0, t0.add(const Duration(minutes: 2))), isFalse);
  });

  testWidgets('a resumed session says so in its badge; a new one needs none (the title says who is connected)',
      (tester) async {
    await tester.pumpWidget(_session(resumed: true));
    expect(find.text('● دوباره وصل شد'), findsOneWidget);
    await tester.pumpWidget(_session());
    expect(find.text('● دوباره وصل شد'), findsNothing);
    expect(find.textContaining('وصل است'), findsOneWidget); // C3: «… وصل است»
    expect(find.text('پایان'), findsOneWidget); // the end button stays
  });
}
