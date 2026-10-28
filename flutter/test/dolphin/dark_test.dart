import 'package:flutter/material.dart';
import 'package:flutter_hbb/dolphin/connection_view.dart';
import 'package:flutter_hbb/dolphin/home_view.dart';
import 'package:flutter_hbb/dolphin/install_view.dart';
import 'package:flutter_hbb/dolphin/technician_id.dart';
import 'package:flutter_hbb/dolphin/theme.dart';
import 'package:flutter_hbb/dolphin/update_view.dart';
import 'package:flutter_hbb/dolphin/verify.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

// DR-1: one theme for all our screens, light as the portal. Whatever Windows' theme is, upstream's dark theme must not
// leak into the prompt, the chips, the session and ended screens, the home, the installer or the update screen.
void main() {
  testWidgets('consent prompt on a dark Windows: every text reaches AA, chips included', (tester) async {
    await tester.pumpWidget(darkApp(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.verified, 'رحمت کهندل'),
        peerName: 'x',
        onAccept: (k, c, f) {},
        onDeny: () {})));
    expectAllTextReadable(tester);
    // The selected chip: label on azureTint.
    // The chip paints its own selectedColor (azureTint); the label colour is what the theme gives it.
    final label = tester.widget<RichText>(find.descendant(of: find.text('کلیپ‌بورد'), matching: find.byType(RichText)).first);
    expect(contrast(Color.alphaBlend(label.text.style!.color!, DolphinColors.azureTint), DolphinColors.azureTint),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets('rejected prompt on a dark Windows: the danger title is readable', (tester) async {
    await tester.pumpWidget(darkApp(DolphinAcceptView(
        verdict: const TechVerdict(TechCheck.rejected),
        peerName: 'x',
        onAccept: (k, c, f) {},
        onDeny: () {})));
    expectAllTextReadable(tester);
  });

  testWidgets('session and ended screens on a dark Windows', (tester) async {
    await tester.pumpWidget(darkApp(DolphinSessionView(
        technician: 'علی',
        elapsed: const Duration(minutes: 4),
        keyboard: true,
        clipboard: false,
        file: true,
        onToggle: (n, v) {},
        onEnd: () {})));
    expectAllTextReadable(tester);
    await tester.pumpWidget(darkApp(DolphinEndedView(reason: DolphinEndReason.you, onClose: () {})));
    expectAllTextReadable(tester);
  });

  testWidgets('home, installer and update screens on a dark Windows', (tester) async {
    await tester.pumpWidget(darkApp(DolphinHomeView(
        id: '123456789',
        state: DolphinServerState.ready,
        onCopy: () {},
        phone: '021-1',
        siteLabel: 'support.dolphindev.ir')));
    expectAllTextReadable(tester);
    await tester.pumpWidget(darkApp(DolphinInstallView(onInstall: () {}, onRunWithoutInstall: () {})));
    expectAllTextReadable(tester);
    await tester.pumpWidget(darkApp(DolphinUpdateView(
        check: const DolphinUpdateCheck(state: 'update', version: '2.0.0', lead: 'نسخه‌ی تازه آماده است', phone: '021-1'),
        progress: const DolphinUpdateProgress(state: 'failed', error: 'خطا'),
        onRetry: () {},
        onDownloadPage: () {},
        onClose: () {},
        onContinue: () {})));
    expectAllTextReadable(tester);
  });

  testWidgets('the technician ID card on a dark Windows is dark ink on white', (tester) async {
    await tester.pumpWidget(darkApp(DolphinTechnicianIdView(id: '287654321', onCopy: () {})));
    expectAllTextReadable(tester);
  });

  test('the palette: one azure, aqua text darkened, every pair reaches AA', () {
    expect(DolphinColors.azure, const Color(0xFF1462E0));
    expect(DolphinColors.aquaText, const Color(0xFF0F766E));
    const white = Colors.white;
    for (final (fg, bg) in [
      (DolphinColors.azure, DolphinColors.azureSoft),
      (DolphinColors.azure, DolphinColors.ground),
      (DolphinColors.azure, white),
      (white, DolphinColors.azure),
      (DolphinColors.aquaText, DolphinColors.aquaSoft),
      (DolphinColors.aquaText, white),
      (DolphinColors.muted, DolphinColors.ground),
      (DolphinColors.muted, DolphinColors.azureSoft),
      (DolphinColors.dangerText, DolphinColors.dangerSoft),
      (white, DolphinColors.danger),
      (DolphinColors.ink, DolphinColors.azureTint),
    ]) {
      expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
    }
  });
}
