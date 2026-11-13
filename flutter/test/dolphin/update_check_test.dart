import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(theme: dolphinTheme(ThemeData.light()), home: Scaffold(body: child));

const _phone = 'اگر درست نشد با پشتیبانی دلفین تماس بگیرید: ۰۲۱-۴۴۲۸۰۵۰۵';

void main() {
  group('what the portal answered (DD-20)', () {
    test('"up to date" only when the portal said so', () {
      expect(ManualUpdateCheck.fromJson('{"state":"current","reason":"latest"}').phase, UpdateCheckPhase.latest);
      expect(ManualUpdateCheck.fromJson('{"state":"current","reason":"disabled"}').phase, UpdateCheckPhase.disabled);
      for (final raw in ['', 'nope', '[1]', '{"state":"current"}', '{"state":"current","reason":"unreachable"}',
          '{"state":"current","reason":7}', '{"state":"surprise"}']) {
        expect(ManualUpdateCheck.fromJson(raw).phase, UpdateCheckPhase.unreachable, reason: raw);
      }
    });

    test('a newer build is found for update, blocked and manual, with the start-up answer kept for the screen', () {
      const raw = '{"state":"update","version":"2.1.0","lead":"پیش از باز شدن برنامه…","phone":"$_phone",'
          '"downloadPage":"https://support.dolphindev.ir/download"}';
      final c = ManualUpdateCheck.fromJson(raw);
      expect(c.phase, UpdateCheckPhase.found);
      expect(c.version, '2.1.0');
      expect(c.screen.state, 'update');
      expect(c.screen.phone, _phone);
      expect(c.screen.downloadPage, 'https://support.dolphindev.ir/download');
      expect(c.screen.lead, inAppLead('2.1.0'), reason: 'the app is open already');
      expect(c.screen.lead, contains('۲.۱.۰'));
      expect(c.screen.lead, isNot(contains('پیش از باز شدن')));

      final blocked = ManualUpdateCheck.fromJson('{"state":"blocked","version":"2.1.0","error":"e"}');
      expect(blocked.phase, UpdateCheckPhase.found);
      expect(blocked.screen.error, 'e');
      expect(blocked.screen.lead, inAppLead('2.1.0'));

      // D13: the technician's file is in the panel; Rust's own text says so and stays.
      final manual = ManualUpdateCheck.fromJson('{"state":"manual","version":"2.1.0","lead":"از پنل دلفین دریافت کنید"}');
      expect(manual.phase, UpdateCheckPhase.found);
      expect(manual.screen.state, 'manual');
      expect(manual.screen.lead, 'از پنل دلفین دریافت کنید');
    });

    test('texts are Persian with Persian digits', () {
      expect(foundText('2.1.0'), 'نسخه‌ی ۲.۱.۰ آماده است.');
      expect(kCheckUpdateLabel, 'بررسی نسخه‌ی تازه');
      expect(kCheckingText, 'در حال بررسی…');
      expect(kUpToDateText, 'نسخه‌ی شما تازه است');
      expect(kUpdateLabel, 'به‌روزرسانی');
    });
  });

  group('the About row', () {
    Future<List<String>> pump(WidgetTester tester, UpdateCheckPhase phase,
        {String version = '', VoidCallback? onCheck, VoidCallback? onUpdate}) async {
      final calls = <String>[];
      await tester.pumpWidget(_app(DolphinUpdateCheckView(
          phase: phase,
          version: version,
          onCheck: onCheck ?? () => calls.add('check'),
          onUpdate: onUpdate ?? () => calls.add('update'))));
      return calls;
    }

    testWidgets('idle shows the check button and asks when tapped', (tester) async {
      final calls = await pump(tester, UpdateCheckPhase.idle);
      expect(find.text(kCheckUpdateLabel), findsOneWidget);
      expect(find.text(kUpdateLabel), findsNothing);
      await tester.tap(find.text(kCheckUpdateLabel));
      expect(calls, ['check']);
    });

    testWidgets('checking shows «در حال بررسی…» and cannot ask twice', (tester) async {
      final calls = await pump(tester, UpdateCheckPhase.checking);
      expect(find.text(kCheckingText), findsOneWidget);
      await tester.tap(find.text(kCheckUpdateLabel));
      expect(calls, isEmpty);
    });

    testWidgets('up to date says so and can check again', (tester) async {
      final calls = await pump(tester, UpdateCheckPhase.latest);
      expect(find.text(kUpToDateText), findsOneWidget);
      await tester.tap(find.text(kCheckAgainLabel));
      expect(calls, ['check']);
    });

    testWidgets('a found version offers «به‌روزرسانی», which starts the update flow', (tester) async {
      final calls = await pump(tester, UpdateCheckPhase.found, version: '2.1.0');
      expect(find.text(foundText('2.1.0')), findsOneWidget);
      await tester.tap(find.text(kUpdateLabel));
      expect(calls, ['update']);
    });

    testWidgets('no answer and a test build say what happened, never «تازه است»', (tester) async {
      await pump(tester, UpdateCheckPhase.unreachable);
      expect(find.text(kCheckUnreachableText), findsOneWidget);
      expect(find.text(kUpToDateText), findsNothing);
      await pump(tester, UpdateCheckPhase.disabled);
      expect(find.text(kCheckDisabledText), findsOneWidget);
      expect(find.text(kUpdateLabel), findsNothing);
    });
  });
}
