import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/panel_bridge.dart';
import 'package:flutter_hbb/dolphin/portal_view.dart';
import 'package:flutter_hbb/dolphin/side_pane.dart';
import 'package:flutter_hbb/dolphin/side_panel.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_test/flutter_test.dart';

const _peer = '123456789';
const _live = SessionState(live: true);

PanelMessage _paste(String text, [String id = _peer]) =>
    parsePanelMessage({'type': 'dolphin-paste', 'text': text, 'id': id})!;

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF1462E0));
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  group('DD-50 paste message from the side pane', () {
    test('a text for a valid ID is taken, Persian and line breaks kept, spaces in the ID dropped', () {
      final m = parsePanelMessage(jsonEncode({'type': 'dolphin-paste', 'text': 'سلام\r\ndir C:\\', 'id': '123 456 789'}));
      expect(m?.type, 'dolphin-paste');
      expect(m?.text, 'سلام\r\ndir C:\\');
      expect(m?.id, _peer);
    });

    test('bad pastes are ignored', () {
      Map<String, dynamic> p(dynamic text, dynamic id) => {'type': 'dolphin-paste', 'text': text, 'id': id};
      expect(parsePanelMessage(p('', _peer)), isNull);
      expect(parsePanelMessage(p('  ', _peer)), isNull);
      expect(parsePanelMessage(p('a\u0000b', _peer)), isNull);
      expect(parsePanelMessage(p('a\u001b[2J', _peer)), isNull);
      expect(parsePanelMessage(p('x', 'abc')), isNull, reason: 'not an ID');
      expect(parsePanelMessage(p('x', null)), isNull);
      expect(parsePanelMessage(p(42, _peer)), isNull);
      expect(parsePanelMessage(p('ب' * 2000, _peer)), isNotNull, reason: 'the limit counts characters');
      expect(parsePanelMessage(p('ب' * 2001, _peer)), isNull);
    });

    test('only this window\'s PC, a live session and the customer\'s switches let it through', () {
      expect(pasteProblem(_paste('x'), _peer, _live), isNull);
      expect(pasteProblem(_paste('x'), '123 456 789', _live), isNull);
      expect(pasteProblem(_paste('x', '987654321'), _peer, _live), kWrongPc);
      expect(pasteProblem(const PanelMessage('dolphin-hello'), _peer, _live), kWrongPc);
      expect(pasteProblem(_paste('x'), _peer, const SessionState(live: false)), kNotLive);
      expect(pasteProblem(_paste('x'), _peer, const SessionState(live: true, paused: true)), kPausedNow);
      expect(pasteProblem(_paste('x'), _peer, const SessionState(live: true, viewOnly: true)), kViewOnly);
      expect(pasteProblem(_paste('x'), _peer, const SessionState(live: true, keyboard: false)), kKeyboardOff);
      expect(pasteProblem(_paste('x'), _peer, const SessionState(live: true, clipboard: false)), kClipboardOff);
    });

    test('the keyboard change needs a live session and the keyboard, not the clipboard', () {
      expect(keyboardProblem(_live), isNull);
      expect(keyboardProblem(const SessionState(live: true, clipboard: false)), isNull);
      expect(keyboardProblem(const SessionState(live: true, keyboard: false)), kKeyboardOff);
      expect(keyboardProblem(const SessionState(live: false)), kNotLive);
      expect(kDolphinKeyboardChoices.map((c) => c.$1), ['fa', 'en']);
    });
  });

  group('the PC\'s answer', () {
    test('a dolphin-panel message box becomes one line; others stay upstream\'s', () {
      expect(panelResultFromMsgBox('dolphin-panel', 'pasted', 'متن چسبانده شد.'), (true, 'متن چسبانده شد.'));
      expect(panelResultFromMsgBox('dolphin-panel', 'switched-fa', 'فارسی شد.')!.$1, isTrue);
      expect(panelResultFromMsgBox('dolphin-panel', 'elevated', 'مدیر')!.$1, isFalse);
      expect(panelResultFromMsgBox('dolphin-panel', 'failed', ''), (false, 'انجام نشد.'));
      expect(panelResultFromMsgBox('dolphin-panel', 'pasted', 'x' * 200), (true, 'انجام شد.'));
      expect(panelResultFromMsgBox('error', 'pasted', 'x'), isNull);
      expect(panelResultFromMsgBox('dolphin-pause', 'dolphin-paused', ''), isNull);
      expect(panelResultFromMsgBox('dolphin-panel', null, 'x'), isNull);
    });
  });

  group('DD-49 the pane', () {
    test('opens only for a portal-shaped ID, at the side page', () {
      expect(sidePanePath(_peer), '/staff/side/123456789');
      expect(sidePanePath('123 456 789'), '/staff/side/123456789');
      expect(sidePanePath('1234@my.server'), isNull);
      expect(sidePanePath('../x'), isNull);
      expect(sideOpenFrom('Y'), isTrue);
      expect(sideOpenFrom(''), isFalse, reason: 'hidden by default');
    });

    test('the side page is a portal page; other origins are not', () {
      const portal = 'https://support.dolphindev.ir';
      expect(isPanelUrl('$portal/staff/side/123456789', portal), isTrue);
      expect(isPanelUrl('$portal/staff/login?next=%2Fstaff%2Fside%2F123456789', portal), isTrue);
      expect(isPanelUrl('https://support.dolphindev.ir.evil.example/staff/side/1', portal), isFalse);
      expect(isPortalPage('https://evil.example/staff/side/123456789', portal), isFalse);
    });

    test('a link with no page reports not loaded and sends nothing', () async {
      final link = DolphinPortalLink();
      expect(link.loaded, isFalse);
      expect(await link.send('{}'), isFalse);
    });

    Widget app(Widget child) => MaterialApp(theme: dolphinTheme(ThemeData.light()), home: Scaffold(body: child));

    testWidgets('closed: the picture has the whole width; open: the pane takes 340 px on the right', (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const picture = ColoredBox(key: Key('picture'), color: Colors.black);
      const pane = ColoredBox(key: Key('pane'), color: Colors.white);
      await tester.pumpWidget(app(const DolphinSideLayout(open: false, pane: pane, child: picture)));
      expect(tester.getSize(find.byKey(const Key('picture'))).width, 1200);
      expect(find.byKey(const Key('pane')), findsNothing);
      await tester.pumpWidget(app(const DolphinSideLayout(open: true, pane: pane, child: picture)));
      expect(tester.getSize(find.byKey(const Key('picture'))).width, 1200 - kDolphinSideWidth);
      expect(tester.getTopLeft(find.byKey(const Key('pane'))).dx, 1200 - kDolphinSideWidth);
      expect(tester.getTopLeft(find.byKey(const Key('picture'))).dx, 0, reason: 'the picture keeps its left origin');
    });

    testWidgets('the strip toggles, takes a screenshot and switches the keyboard; the notice shows', (tester) async {
      var toggled = 0, shots = 0;
      String? lang;
      Widget strip({bool busy = false}) => DolphinSideStrip(
          open: false,
          shotBusy: busy,
          onToggle: () => toggled++,
          onScreenshot: () => shots++,
          onKeyboard: (l) => lang = l);
      await tester.pumpWidget(app(DolphinSideLayout(
          open: false, strip: strip(), notice: 'زبان صفحه‌کلید مشتری فارسی شد.', child: const SizedBox.expand())));
      await tester.tap(find.byKey(DolphinSideStrip.toggleKey));
      await tester.tap(find.byKey(DolphinSideStrip.shotKey));
      await tester.tap(find.byKey(DolphinSideStrip.keyboardKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فارسی'));
      await tester.pumpAndSettle();
      expect((toggled, shots, lang), (1, 1, 'fa'));
      expect(find.text('زبان صفحه‌کلید مشتری فارسی شد.'), findsOneWidget);
      expect(find.byTooltip('پنل مشتری'), findsOneWidget);
      await tester.pumpWidget(app(DolphinSideLayout(open: false, strip: strip(busy: true), child: const SizedBox.expand())));
      await tester.tap(find.byKey(DolphinSideStrip.shotKey));
      expect(shots, 1, reason: 'no second request while one is on its way');
    });
  });

  group('DD-51 the screenshot', () {
    test('size rules follow the portal\'s base64 limit', () {
      expect(base64Length(3), 4);
      expect(base64Length(4), 8);
      final maxRaw = kScreenshotMaxBase64 * 3 ~/ 4;
      expect(screenshotFits(maxRaw), isTrue);
      expect(screenshotFits(maxRaw + 1), isFalse);
      expect(screenshotTargetWidth(1000, 1920), isNull, reason: 'fits already');
      final t = screenshotTargetWidth(maxRaw * 4, 3840)!;
      expect(t, lessThan(3840 ~/ 2), reason: 'four times the area allowed: under half the width, with a margin');
      expect(t, greaterThanOrEqualTo(480));
      expect(screenshotTargetWidth(maxRaw * 4, 480), isNull, reason: 'too small to scale further');
    });

    test('a screenshot is offered only when it can be taken', () {
      expect(screenshotProblem(live: true, supported: true, allDisplays: false), isNull);
      expect(screenshotProblem(live: false, supported: true, allDisplays: false), kNotLive);
      expect(screenshotProblem(live: true, supported: false, allDisplays: false), isNotNull);
      expect(screenshotProblem(live: true, supported: true, allDisplays: true), contains('یک صفحه'));
    });

    test('the message is the portal\'s shape, and upstream saves to the path given', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
      expect(isPng(png), isTrue);
      expect(isPng(Uint8List.fromList(utf8.encode('GIF89a......'))), isFalse);
      final m = jsonDecode(screenshotMessage(base64Encode(png), '123 456 789')) as Map;
      expect(m['type'], 'dolphin-screenshot');
      expect(m['id'], _peer);
      expect(RegExp(r'^iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$').hasMatch(m['png'] as String), isTrue,
          reason: 'app/src/lib/app-bridge.ts PNG_BASE64');
      expect(screenshotSaveAction(r'C:\Temp\dolphin-shot-1\shot.png'), r'0:C:\Temp\dolphin-shot-1\shot.png');
    });

    testWidgets('a picture that fits is sent as it is; anything that is not a PNG is not sent', (tester) async {
      await tester.runAsync(() async {
        final small = await _png(64, 48);
        expect(await fitScreenshot(small), same(small));
        expect(await fitScreenshot(Uint8List.fromList(utf8.encode('not a picture at all'))), isNull);
      });
    });

    testWidgets('a picture over the limit is scaled down until it fits', (tester) async {
      await tester.runAsync(() async {
        // Noise does not compress: 1400 × 1000 pixels make a PNG over the portal's limit.
        const w = 1400, h = 1000;
        var seed = 7;
        final pixels = Uint8List(w * h * 4);
        for (var i = 0; i < pixels.length; i++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          pixels[i] = (i % 4 == 3) ? 255 : (seed >> 16) & 0xff;
        }
        final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
        final descriptor = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
        final image = (await (await descriptor.instantiateCodec()).getNextFrame()).image;
        final big = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        image.dispose();
        expect(screenshotFits(big.length), isFalse, reason: 'the test picture must be over the limit');
        final fitted = await fitScreenshot(big);
        expect(fitted, isNotNull);
        expect(isPng(fitted!), isTrue);
        expect(screenshotFits(fitted.length), isTrue);
      });
    });
  });
}
