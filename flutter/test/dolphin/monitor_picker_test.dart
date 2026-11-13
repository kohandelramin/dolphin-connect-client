import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/monitor_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// DD-52: the customer's screens as pictures of their layout.
void main() {
  const left = DolphinScreen(x: 0, y: 0, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080);
  const right = DolphinScreen(x: 1920, y: 0, width: 1280, height: 1024, pixelWidth: 2560, pixelHeight: 2048);

  test('the layout keeps the arrangement and proportions and fits the box', () {
    final r = screenLayout([left, right], const Size(320, 150), gap: 0);
    expect(r, hasLength(2));
    // Side by side, left screen on the left (never mirrored for RTL).
    expect(r[0].left, lessThan(r[1].left));
    expect(r[0].right, closeTo(r[1].left, 0.001));
    // Proportions: 1920 wide vs 1280 wide.
    expect(r[0].width / r[1].width, closeTo(1.5, 0.001));
    // Fits the box: total width 3200 → 320, height 1080 → 108, centred vertically.
    expect(r[0].left, closeTo(0, 0.001));
    expect(r[1].right, closeTo(320, 0.001));
    expect(r[0].top, closeTo((150 - 108) / 2, 0.001));
    for (final x in r) {
      expect(x.right, lessThanOrEqualTo(320.001));
      expect(x.bottom, lessThanOrEqualTo(150.001));
    }
  });

  test('a gap between screens, and nothing odd for empty or flat input', () {
    final r = screenLayout([left, right], const Size(320, 150), gap: 4);
    expect(r[1].left - r[0].right, closeTo(4, 0.001));
    expect(screenLayout(const [], const Size(10, 10)), isEmpty);
    expect(screenLayout(const [DolphinScreen(x: 0, y: 0, width: 0, height: 0, pixelWidth: 0, pixelHeight: 0)],
        const Size(10, 10)), [Rect.zero]);
  });

  test('labels in Persian digits', () {
    expect(screenName(0), 'صفحه‌ی ۱');
    expect(screenSize(right), '۲۵۶۰ × ۲۰۴۸');
  });

  for (final (name, app) in [('light', lightApp), ('dark', darkApp)]) {
    testWidgets('the picker in the $name theme: current marked, «اصلی», tap picks another, AA', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(app(Center(
          child: DolphinMonitorPicker(screens: const [left, right], current: 1, primary: 0, onPick: picked.add))));
      expect(find.text('صفحه‌های مشتری'), findsOneWidget);
      expect(find.text('۱'), findsOneWidget);
      expect(find.text('۲'), findsOneWidget);
      expect(find.text('اصلی'), findsOneWidget);
      expect(find.byTooltip('صفحه‌ی ۲ (همین را می‌بینید)'), findsOneWidget);
      expectAllTextReadable(tester);
      await tester.tap(find.text('۲')); // the current one: nothing
      await tester.tap(find.text('۱'));
      expect(picked, [0]);
    });
  }
}
