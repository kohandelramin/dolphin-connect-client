import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/request_outcome.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: dolphinTheme(ThemeData.light()), home: Scaffold(body: child));

void main() {
  test('«رد» on a waiting request is «مشتری رد کرد»; the same words after a login are not (DD-14)', () {
    bool denied({bool technician = true, bool waiting = true, String title = 'Connection Error',
            String text = 'Closed manually by the peer'}) =>
        dolphinRequestDenied(technician: technician, waitingForAccept: waiting, title: title, text: text);
    expect(denied(), isTrue);
    expect(denied(waiting: false), isFalse); // «پایان» in a session: upstream's «مشتری اتصال را بست»
    expect(denied(technician: false), isFalse);
    expect(denied(text: 'Closed manually by web console'), isFalse); // the portal's cut
    expect(denied(text: 'Reset by the peer'), isFalse);
    expect(denied(title: 'Prompt'), isFalse);
  });

  test('the wait is counted in Persian digits', () {
    expect(dolphinWaitedText(const Duration(seconds: 7)), '۷ ثانیه');
    expect(dolphinWaitedText(const Duration(seconds: 65)), '۱:۰۵');
    expect(dolphinWaitedText(const Duration(seconds: -1)), '۰ ثانیه');
  });

  testWidgets('waiting, then «مشتری جواب نداد» with what to do; nothing is ended', (tester) async {
    var now = DateTime(2026, 11, 13, 10);
    await tester.pumpWidget(_app(DolphinWaitAccept(now: () => now)));
    expect(find.text(kDolphinWaitingTitle), findsOneWidget);
    expect(find.text(kDolphinNoAnswerHint), findsNothing);

    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(kDolphinWaitingTitle), findsOneWidget);
    expect(find.text('۳۰ ثانیه'), findsOneWidget);

    now = now.add(kDolphinNoAnswerAfter);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(kDolphinNoAnswerTitle), findsOneWidget);
    expect(find.text(kDolphinNoAnswerHint), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing); // the dialog's own «لغو» stays the only way out

    await tester.pumpWidget(const SizedBox()); // the timer stops with the dialog
  });
}
