import 'package:flutter/material.dart';

/// Dolphin's palette: the portal's tokens (app/src/app/globals.css), the website's system in a lighter blue.
class DolphinColors {
  static const azure = Color(0xFF1462E0); // the one primary blue (D20): fills and text; white on it 5.45:1, on azureSoft 4.97:1
  static const azureSoft = Color(0xFFEEF5FF);
  static const azureTint = Color(0xFFD9E8FF);
  static const aqua = Color(0xFF0D9488); // fills and icons only (3.74:1 on white)
  static const aquaText = Color(0xFF0F766E); // small aqua text (5.47:1 on white, 4.91:1 on aquaSoft)
  static const aquaSoft = Color(0xFFE6F6F4);
  static const ink = Color(0xFF0B1829);
  static const msgSuccess = aquaText; // message-box success icon/fill: white on it 5.47:1 (upstream #32bea6 was 2.3:1)
  static const msgError = Color(0xFFD03C4E); // message-box error: white on it 4.73:1 (upstream #E04F5F was 3.9:1)
  static const danger = Color(0xFFE11D48);
  static const dangerText = Color(0xFFBE123C);
  static const dangerSoft = Color(0xFFFFF0F3);
  static const ground = Color(0xFFF6F9FF);
  static const muted = Color(0xFF52637A);
  static const line = Color(0xFFE2E9F3);
  static const lineStrong = Color(0xFFC8D6E8);
}

/// The portal's radii: fields 10, controls 12, cards 18.
class DolphinRadii {
  static const field = 10.0;
  static const control = 12.0;
  static const card = 18.0;
}

/// Embedded in the app (assets/fonts), so it renders the same on every Windows.
const kDolphinFont = 'Vazirmatn';

/// Dolphin's look over the upstream theme: Vazirmatn everywhere, azure and aqua as the brand colours.
ThemeData dolphinTheme(ThemeData base) {
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
        primary: DolphinColors.azure,
        secondary: DolphinColors.aqua,
        error: DolphinColors.danger),
    textTheme: base.textTheme.apply(fontFamily: kDolphinFont),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kDolphinFont),
  );
}

/// The one theme of all our screens, whatever Windows' theme is (DR-1, owner 2026-10-28): light, as the portal.
/// Upstream's app follows the system theme, and in dark mode its text, scaffold and chip colours leaked into our
/// views (white on white, 1.24:1 chips). Every Dolphin view wraps itself in this, so no view depends on the app theme.
/// [paint] fills the view with the ground colour; false for overlays (permission strip, call status) that sit over
/// something else and only need the light text defaults.
class DolphinLight extends StatelessWidget {
  final Widget child;
  final bool paint;
  const DolphinLight({super.key, required this.child, this.paint = true});

  static final ThemeData data = dolphinTheme(ThemeData(brightness: Brightness.light, useMaterial3: false));

  @override
  Widget build(BuildContext context) => Theme(
        data: data,
        child: paint
            ? Material(color: DolphinColors.ground, child: child)
            : Material(type: MaterialType.transparency, child: child),
      );
}
