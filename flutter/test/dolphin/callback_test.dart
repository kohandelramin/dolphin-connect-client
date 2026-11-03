import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/callback.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/tech_card.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

// SOI, then EOI: enough for techPhoto's check; the widget tests never decode it.
final _jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xD9]);

void main() {
  test('only a linked PC shows the callback button', () {
    expect(callbackShown('Y'), isTrue);
    expect(callbackShown('-'), isFalse);
    expect(callbackShown(''), isFalse);
  });

  test('the form checks name and phone the way the app\'s Rust side does', () {
    expect(callbackProblem('خانم رضایی', '۰۹۱۲ ۳۴۵ ۶۷۸۹'), isNull);
    expect(callbackProblem('علی', '+98 (912) 345-6789'), isNull);
    expect(callbackProblem('  ', '09123456789'), isNotNull);
    expect(callbackProblem('علی', '12'), isNotNull);
    expect(callbackProblem('ن' * 61, '09123456789'), isNotNull);
  });

  test('the sender\'s state reads safely', () {
    expect(CallbackStatus.fromJson('{"state":"done","text":"ثبت شد"}').phase, CallbackPhase.done);
    expect(CallbackStatus.fromJson('{"state":"failed","text":"x"}').text, 'x');
    expect(CallbackStatus.fromJson('nonsense').phase, CallbackPhase.idle);
  });

  test('a photo is used only when it is a small JPEG', () {
    expect(techPhoto(_jpeg), isNotNull);
    expect(techPhoto('-'), isNull);
    expect(techPhoto(''), isNull);
    expect(techPhoto('not base64!'), isNull);
    expect(techPhoto(base64Encode(utf8.encode('<svg/>'))), isNull);
  });

  test('the card shows while a technician may connect and nobody is connected', () {
    const now = 1000000;
    TechComing? at({String id = '123456789', int until = now + 600, int? connected = 0}) =>
        techComing(techId: id, techName: 'رحمت', until: until, nowSeconds: now, connected: connected, photo: _jpeg);
    expect(at()?.name, 'رحمت');
    expect(at()?.photo, isNotNull);
    expect(at(id: '-'), isNull);
    expect(at(connected: 1), isNull);
    expect(at(until: now - 3600), isNull);
  });

  testWidgets('home: the card names the technician; the callback button shows only without one', (tester) async {
    var opened = false;
    Widget home({TechComing? coming}) => _app(DolphinHomeView(
          id: '123456789',
          state: DolphinServerState.ready,
          onCopy: () {},
          phone: '',
          siteLabel: 'x',
          coming: coming,
          onCallback: () => opened = true,
        ));
    await tester.pumpWidget(home());
    await tester.tap(find.text(kCallbackLabel));
    expect(opened, isTrue);
    await tester.pumpWidget(home(coming: const TechComing('رحمت کهندل', null)));
    expect(find.text('کارشناس دلفین در راه است'), findsOneWidget);
    expect(find.textContaining('رحمت کهندل'), findsOneWidget);
    expect(find.text(kCallbackLabel), findsNothing);
  });

  testWidgets('the form refuses a bad phone, then sends and shows the answer', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(_app(DolphinCallbackForm(
      onSend: (name, phone, note) async {
        sent.add('$name|$phone|$note');
        return const CallbackStatus(CallbackPhase.done, 'درخواست شما ثبت شد');
      },
      onClose: () {},
    )));
    await tester.enterText(find.byType(TextField).at(0), 'خانم رضایی');
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.tap(find.text('فرستادن'));
    await tester.pump();
    expect(sent, isEmpty);
    expect(find.textContaining('شماره‌ی تلفن را درست'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), '09123456789');
    await tester.tap(find.text('فرستادن'));
    await tester.pumpAndSettle();
    expect(sent, ['خانم رضایی|09123456789|']);
    expect(find.text('درخواست شما ثبت شد'), findsOneWidget);
    expect(find.text('بستن'), findsOneWidget);
  });
}
