import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/chat.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Scaffold(body: child),
    );

void main() {
  test('each message reads in its own direction (DD-29)', () {
    expect(chatTextDirection('سلام، فایل را فرستادم'), TextDirection.rtl);
    expect(chatTextDirection(r'C:\Program Files\Dolphin'), TextDirection.ltr);
    expect(chatTextDirection('Error 5: access denied'), TextDirection.ltr);
    expect(chatTextDirection('۱۲۳ تومان'), TextDirection.rtl); // digits are weak, the first letter decides
    expect(chatTextDirection('123 OK'), TextDirection.ltr);
    expect(chatTextDirection('«پوشه» Downloads'), TextDirection.rtl);
    expect(chatTextDirection('123 !?'), TextDirection.rtl); // no letter: the chat's own direction
    expect(chatTextDirection(''), TextDirection.rtl);
  });

  test('the time is in Persian digits', () {
    expect(chatTime(DateTime(2026, 11, 13, 9, 5)), '۹:۰۵');
    expect(chatTime(DateTime(2026, 11, 13, 14, 30)), '۱۴:۳۰');
  });

  test('the small corner points at the sender: ours on the left, theirs on the right', () {
    final ours = chatBubbleCorners(ours: true);
    expect(ours.bottomLeft, lessThan(ours.bottomRight));
    final theirs = chatBubbleCorners(ours: false);
    expect(theirs.bottomRight, lessThan(theirs.bottomLeft));
  });

  test('an incoming message is shown at once, without leaving a live conversation', () {
    expect(chatFollowsIncoming(sameAsCurrent: false, currentLive: false), isTrue); // the chat showed an ended session
    expect(chatFollowsIncoming(sameAsCurrent: false, currentLive: true), isFalse);
    expect(chatFollowsIncoming(sameAsCurrent: true, currentLive: false), isFalse);
  });

  testWidgets('an empty chat says how to start, right to left, and lets the input through', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(DolphinChatFrame(
        empty: true, child: Center(child: TextButton(onPressed: () => tapped = true, child: const Text('x'))))));
    expect(find.text(kChatEmpty), findsOneWidget);
    final dir = tester.widget<Directionality>(
        find.ancestor(of: find.text(kChatEmpty), matching: find.byType(Directionality)).first);
    expect(dir.textDirection, TextDirection.rtl);
    await tester.tap(find.text('x'));
    expect(tapped, isTrue);

    await tester.pumpWidget(_app(const DolphinChatFrame(empty: false, child: SizedBox())));
    expect(find.text(kChatEmpty), findsNothing);
  });

  testWidgets('a bubble shows the text in Vazirmatn in its direction, and the time', (tester) async {
    await tester.pumpWidget(_app(DolphinChatText(text: r'D:\Setup.exe', at: DateTime(2026, 1, 1, 8, 7))));
    final text = tester.widget<Text>(find.text(r'D:\Setup.exe'));
    expect(text.textDirection, TextDirection.ltr);
    expect(text.style?.fontFamily, kDolphinFont);
    expect(find.text('۸:۰۷'), findsOneWidget);
  });

  testWidgets('the customer opens the chat from the session window; no button without a chat', (tester) async {
    var opened = 0;
    Widget view({VoidCallback? onChat}) => _app(SizedBox(
          width: 300,
          height: 380,
          child: DolphinSessionView(
              technician: 'علی',
              elapsed: Duration.zero,
              keyboard: true,
              clipboard: true,
              file: true,
              onToggle: (_, __) {},
              onEnd: () {},
              onChat: onChat),
        ));
    await tester.pumpWidget(view(onChat: () => opened++));
    await tester.tap(find.text(kDolphinChatLabel));
    expect(opened, 1);
    expect(find.text('پایان'), findsOneWidget); // still pinned

    await tester.pumpWidget(view());
    expect(find.text(kDolphinChatLabel), findsNothing);
  });
}
