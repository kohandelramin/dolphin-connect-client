import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/file_transfer.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
      theme: dolphinTheme(ThemeData.light()),
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  group('drag and drop (DD-30)', () {
    const file = (path: r'C:\Users\t\Desktop\setup.exe', name: 'setup.exe', isDir: false, size: 1200);
    const folder = (path: r'C:\Users\t\Desktop\Dolphin', name: 'Dolphin', isDir: true, size: 0);

    test('a drop goes to the open folder on the customer PC; nothing while that folder is not known', () {
      expect(dropToSend([file, folder], r'C:\Users\Ali\Downloads\دریافتی دلفین'), [file, folder]);
      expect(dropToSend([file], ''), isEmpty);
      expect(dropToSend([file], '  '), isEmpty);
    });

    test('a whole drive is never sent', () {
      const drive = (path: r'D:\', name: 'D:', isDir: true, size: 0);
      expect(dropToSend([drive, file], r'C:\x'), [file]);
    });

    testWidgets('the mask names the destination', (tester) async {
      await tester.pumpWidget(_app(const DolphinDropMask(remoteFolder: r'C:\Users\Ali\Downloads')));
      expect(find.text(kDropTitle), findsOneWidget);
      expect(find.text(r'C:\Users\Ali\Downloads'), findsOneWidget);
      await tester.pumpWidget(_app(const DolphinDropMask(remoteFolder: '')));
      expect(find.text(kDropNoFolder), findsOneWidget);
    });
  });

  group('the queue', () {
    test('percent and files in Persian', () {
      expect(transferPercent(0.456), '۴۶٪');
      expect(transferPercent(0), '۰٪');
      expect(transferPercent(1.2), '۱۰۰٪');
      expect(transferFiles(2, 5), '۲ از ۵ فایل');
    });

    test('each state has its buttons: stop while running, retry after a failure or a stop', () {
      List<DolphinJobAction> a(String state, {String err = '', bool retry = true, String type = 'transfer'}) =>
          jobActions(type: type, state: state, err: err, canRetry: retry);
      expect(a('inProgress'), [DolphinJobAction.stop]);
      expect(a('none'), [DolphinJobAction.stop]);
      expect(a('paused'), [DolphinJobAction.resume, DolphinJobAction.stop]);
      expect(a('error'), [DolphinJobAction.retry, DolphinJobAction.remove]);
      expect(a('error', retry: false), [DolphinJobAction.remove]); // a job from before this window: no request kept
      expect(a('done', err: 'cancel'), [DolphinJobAction.retry, DolphinJobAction.remove]);
      expect(a('done'), [DolphinJobAction.remove]);
      expect(a('done', err: 'skipped'), [DolphinJobAction.remove]);
      expect(a('inProgress', type: 'deleteFile'), [DolphinJobAction.remove]);
    });

    testWidgets('the buttons say what they do in Persian and call back', (tester) async {
      final pressed = <DolphinJobAction>[];
      await tester.pumpWidget(_app(DolphinJobButtons(
          actions: const [DolphinJobAction.retry, DolphinJobAction.remove], onAction: pressed.add)));
      expect(find.byTooltip(kJobRetry), findsOneWidget);
      expect(find.byTooltip(kJobRemove), findsOneWidget);
      expect(find.byTooltip(kJobStop), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dolphin-job-retry')));
      expect(pressed, [DolphinJobAction.retry]);
    });
  });

  group('pinned folders', () {
    test('kept per side, survive bad data, one pin per folder, at most twelve', () {
      expect(pinsFor('', 'remote'), isEmpty);
      expect(pinsFor('not json', 'remote'), isEmpty);
      expect(pinsFor('{"remote": [1, "", "C:\\\\Dolphin"]}', 'remote'), [r'C:\Dolphin']);
      var stored = withPins('', 'remote', [r'C:\Program Files\Dolphin']);
      stored = withPins(stored, 'local', [r'D:\Installers']);
      expect(pinsFor(stored, 'remote'), [r'C:\Program Files\Dolphin']);
      expect(pinsFor(stored, 'local'), [r'D:\Installers']);

      var pins = addPin(const [], r'C:\Program Files\Dolphin');
      expect(addPin(pins, r'c:\program files\dolphin\'), pins); // same folder on Windows
      expect(isPinned(pins, r'C:\Program Files\Dolphin\'), isTrue);
      expect(removePin(pins, r'c:\Program Files\Dolphin'), isEmpty);
      expect(addPin(pins, '  '), pins);

      for (var i = 0; i < 20; i++) {
        pins = addPin(pins, 'C:\\f$i');
      }
      expect(pins.length, kMaxPins);
      expect(pins.last, r'C:\f19');
      expect(isPinned(pins, r'C:\Program Files\Dolphin'), isFalse); // the oldest went
    });

    testWidgets('the menu pins this folder, opens a pin and unpins it', (tester) async {
      var stored = '';
      final opened = <String>[];
      Widget menu(String here) => _app(Center(
          child: DolphinPinMenu(
              side: 'remote',
              current: () => here,
              onOpen: opened.add,
              load: () => stored,
              save: (v) => stored = v)));

      await tester.pumpWidget(menu(r'C:\Program Files\Dolphin'));
      await tester.tap(find.byKey(const ValueKey('dolphin-pins-remote')));
      await tester.pumpAndSettle();
      expect(find.text(kPinsEmpty), findsOneWidget);
      await tester.tap(find.text(kPinThis));
      await tester.pumpAndSettle();
      expect(pinsFor(stored, 'remote'), [r'C:\Program Files\Dolphin']);

      await tester.pumpWidget(menu(r'C:\Users'));
      await tester.tap(find.byKey(const ValueKey('dolphin-pins-remote')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'C:\Program Files\Dolphin'));
      await tester.pumpAndSettle();
      expect(opened, [r'C:\Program Files\Dolphin']);

      await tester.tap(find.byKey(const ValueKey('dolphin-pins-remote')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(kUnpin));
      await tester.pumpAndSettle();
      expect(pinsFor(stored, 'remote'), isEmpty);
      expect(pinsFor(stored, 'local'), isEmpty);
    });
  });
}
