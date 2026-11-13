import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/session_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// DD-28: the Persian quick bar of the technician's session toolbar.
void main() {
  test('latency: the quality monitor delay, in Persian digits, display only', () {
    expect(parseDelay('45'), 45);
    expect(parseDelay(' 7 '), 7);
    expect(parseDelay(''), isNull);
    expect(parseDelay(null), isNull);
    expect(parseDelay('-1'), isNull);
    expect(parseDelay('x'), isNull);
    expect(latencyLabel(45), '۴۵ میلی‌ثانیه');
    expect(latencyLabel(null), '—');
    expect(latencyLevel(80), DolphinLatency.good);
    expect(latencyLevel(150), DolphinLatency.good);
    expect(latencyLevel(151), DolphinLatency.fair);
    expect(latencyLevel(400), DolphinLatency.fair);
    expect(latencyLevel(401), DolphinLatency.slow);
  });

  test('route: direct or through the Dolphin server', () {
    expect(routeLabel(true), 'مستقیم');
    expect(routeLabel(false), 'از سرور دلفین');
    expect(routeLabel(null), isNull);
    expect(latencyTooltip(45, false), contains('relay'));
    expect(latencyTooltip(45, true), contains(kLatencyNote));
  });

  Future<void> pumpBar(WidgetTester tester, Widget bar, {Widget Function(Widget) app = lightApp}) async {
    tester.view.physicalSize = const Size(2400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(Center(child: bar)));
  }

  testWidgets('every button has its Persian tooltip and fires its action', (tester) async {
    final fired = <String>[];
    await pumpBar(
        tester,
        DolphinSessionBar(
          state: const DolphinBarState(latencyMs: 45, direct: true, canFollow: true),
          onCtrlAltDel: () => fired.add('cad'),
          onLock: () => fired.add('lock'),
          onFiles: () => fired.add('files'),
          onViewOnly: () => fired.add('view'),
          onMyCursor: () => fired.add('cursor'),
          onFollow: () => fired.add('follow'),
          onNoPicture: () => fired.add('help'),
          onCollapse: () => fired.add('collapse'),
          onScreenshot: () => fired.add('shot'),
          onKeyboardLayout: () => fired.add('kb'),
        ));
    expect(find.text('۴۵ میلی‌ثانیه'), findsOneWidget);
    expect(find.text('مستقیم'), findsOneWidget);
    for (final (tip, key) in [
      (DolphinBarText.ctrlAltDel, 'cad'),
      (DolphinBarText.lock, 'lock'),
      (DolphinBarText.files, 'files'),
      ('${DolphinBarText.viewOnly}: خاموش', 'view'),
      ('${DolphinBarText.myCursor}: خاموش', 'cursor'),
      ('${DolphinBarText.follow}: خاموش', 'follow'),
      (DolphinBarText.noPicture, 'help'),
      (DolphinBarText.collapse, 'collapse'),
      (DolphinBarText.screenshot, 'shot'),
      (DolphinBarText.keyboardLayout, 'kb'),
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      await tester.tap(find.byTooltip(tip));
      expect(fired.last, key, reason: tip);
    }
  });

  testWidgets('toggles show their state; follow needs several screens', (tester) async {
    await pumpBar(
        tester,
        DolphinSessionBar(
          state: const DolphinBarState(viewOnly: true, myCursor: true, follow: false, canFollow: false),
          onViewOnly: () {},
          onMyCursor: () {},
          onFollow: () {},
        ));
    expect(find.byTooltip('${DolphinBarText.viewOnly}: روشن'), findsOneWidget);
    expect(find.byTooltip('${DolphinBarText.myCursor}: روشن'), findsOneWidget);
    final follow = tester.widget<DolphinBarButton>(find.ancestor(
        of: find.byIcon(Icons.center_focus_strong_outlined), matching: find.byType(DolphinBarButton)));
    expect(follow.onPressed, isNull);
    expect(follow.tooltip, DolphinBarText.followNeedsScreens);
  });

  testWidgets('p3-panel buttons are there but disabled until wired, «(به‌زودی)» in the tooltip', (tester) async {
    await pumpBar(tester, const DolphinSessionBar(state: DolphinBarState()));
    expect(find.byTooltip('${DolphinBarText.screenshot} ${DolphinBarText.notReady}'), findsOneWidget);
    expect(find.byTooltip('${DolphinBarText.keyboardLayout} ${DolphinBarText.notReady}'), findsOneWidget);
    for (final b in tester.widgetList<DolphinBarButton>(find.byType(DolphinBarButton))) {
      expect(b.onPressed, isNull, reason: b.tooltip);
    }
    // No collapse button without a handler, no «صفحه‌ها» with one screen.
    expect(find.byTooltip(DolphinBarText.collapse), findsNothing);
    expect(find.byTooltip(DolphinBarText.screens), findsNothing);
    expect(find.text('—'), findsOneWidget); // no latency yet
  });

  testWidgets('«صفحه‌ها» from two screens opens the picker menu', (tester) async {
    var closed = false;
    await pumpBar(
        tester,
        DolphinSessionBar(
          state: const DolphinBarState(screens: 2),
          screensMenu: (context, close) => TextButton(
              onPressed: () {
                closed = true;
                close();
              },
              child: const Text('picker')),
        ));
    expect(find.byTooltip(DolphinBarText.screens), findsOneWidget);
    await tester.tap(find.byTooltip(DolphinBarText.screens));
    await tester.pumpAndSettle();
    await tester.tap(find.text('picker'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(find.text('picker'), findsNothing);
  });

  for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
    testWidgets('the bar in the $name theme: every text reaches AA, slow latency too', (tester) async {
      for (final ms in [45, 300, 900, null]) {
        await pumpBar(
            tester,
            DolphinSessionBar(
              state: DolphinBarState(latencyMs: ms, direct: false),
              onCtrlAltDel: () {},
            ),
            app: app);
        await tester.pumpAndSettle();
        expectAllTextReadable(tester);
      }
    });
  }
}
