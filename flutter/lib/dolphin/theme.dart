import 'package:flutter/material.dart';

/// Dolphin's palette (the dolphindev.ir website's tokens).
class DolphinColors {
  static const azure = Color(0xFF1462E0);
  static const aqua = Color(0xFF0D9488);
  static const ink = Color(0xFF0B1B33);
  static const danger = Color(0xFFE11D48);
  static const ground = Color(0xFFF6F7FB);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE5E8EF);
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
