import 'package:flutter/material.dart';

/// Dolphin's palette: the portal's tokens (app/src/app/globals.css), the website's system in a lighter blue.
class DolphinColors {
  static const azure = Color(0xFF1F6FF0); // primary; white text on it is 4.57:1
  static const azureStrong = Color(0xFF1462E0);
  static const azureSoft = Color(0xFFEEF5FF);
  static const azureTint = Color(0xFFD9E8FF);
  static const aqua = Color(0xFF0D9488);
  static const aquaText = Color(0xFF0F766E);
  static const aquaSoft = Color(0xFFE6F6F4);
  static const ink = Color(0xFF0B1829);
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
