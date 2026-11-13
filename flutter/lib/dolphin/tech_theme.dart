import 'package:flutter/material.dart';

import 'theme.dart';

/// DD-53: the technician app's colours, light and dark. The customer's screens stay light whatever Windows says (DR-1);
/// the technician, who sits in front of the app all day, chooses: «مثل ویندوز» (the default), «روشن» or «تیره».
/// Every pair a view uses is checked for contrast in test/dolphin/tech_theme_test.dart. Plan 19: the colours come from
/// the theme tokens (theme_tokens.dart), so the portal's theme reaches the technician app too.
class DolphinTechPalette {
  final Brightness brightness;
  final Color ground; // behind everything
  final Color surface; // header, cards, the toolbar's own chips
  final Color ink; // body text
  final Color muted; // secondary text
  final Color line; // hairlines
  final Color lineStrong; // field and outlined-button borders
  final Color accent; // azure as text or an icon on [surface] or [ground]
  final Color accentSoft; // a quiet azure fill behind [accent] text
  final Color okText; // «خوب» (aqua) as text on [surface]
  final Color warnText; // amber as text on [surface]
  final Color dangerText; // red as text on [surface]
  final Color fill; // the brand blue as a fill (selected chips); white text on it
  final double radiusSmall; // the toolbar's chips (8 built in)
  final double radiusTiny; // the screen picker's tiles (6 built in)

  const DolphinTechPalette._({
    required this.brightness,
    required this.ground,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineStrong,
    required this.accent,
    required this.accentSoft,
    required this.okText,
    required this.warnText,
    required this.dangerText,
    required this.fill,
    required this.radiusSmall,
    required this.radiusTiny,
  });

  /// The palette of one token set (theme_tokens.dart): the built-in light one is the portal's own tokens, the
  /// built-in dark one the website's ink ground with azure and aqua lifted, both as before Plan 19.
  factory DolphinTechPalette.fromTokens(DolphinThemeTokens t) => DolphinTechPalette._(
        brightness: t.brightness,
        ground: t.background,
        surface: t.surface,
        ink: t.text,
        muted: t.textMuted,
        line: t.line,
        lineStrong: t.lineStrong,
        accent: t.primaryText,
        accentSoft: t.surfaceAlt,
        okText: t.success,
        warnText: t.warning,
        dangerText: t.danger,
        fill: t.primary,
        radiusSmall: t.radiusSmall,
        radiusTiny: t.radiusTiny,
      );

  /// The tokens in use (built-in, or the portal's theme while it is in use).
  static DolphinTechPalette get light => DolphinTechPalette.fromTokens(DolphinTheme.light);
  static DolphinTechPalette get dark => DolphinTechPalette.fromTokens(DolphinTheme.dark);

  static DolphinTechPalette of(Brightness b) => b == Brightness.dark ? dark : light;

  /// The palette of the theme around [context] (the app's, which follows the technician's choice).
  static DolphinTechPalette ofContext(BuildContext context) => of(Theme.of(context).brightness);
}

/// What the switch says for each choice.
String themeModeLabel(ThemeMode m) => switch (m) {
      ThemeMode.system => 'مثل ویندوز',
      ThemeMode.light => 'روشن',
      ThemeMode.dark => 'تیره',
    };

/// The brightness a choice gives on a Windows whose own theme is [platform].
Brightness techBrightness(ThemeMode m, Brightness platform) => switch (m) {
      ThemeMode.system => platform,
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };

/// The technician app's counterpart of [DolphinLight]: our fonts and buttons in the brightness of the theme around it
/// (the app's theme mode, which upstream's `theme` option drives and the switch below sets). [paint] as in DolphinLight.
class DolphinTechTheme extends StatelessWidget {
  final Widget child;
  final bool paint;
  const DolphinTechTheme({super.key, required this.child, this.paint = true});

  static DolphinThemeTokens? _darkFor;
  static ThemeData? _darkData;

  /// Built once per token set, as [DolphinLight.data].
  static ThemeData get darkData {
    final t = DolphinTheme.dark;
    if (!identical(t, _darkFor) || _darkData == null) {
      final p = DolphinTechPalette.fromTokens(t);
      _darkData = dolphinButtons(
          dolphinTheme(ThemeData(brightness: Brightness.dark, useMaterial3: false)).copyWith(
              scaffoldBackgroundColor: p.ground,
              canvasColor: p.surface,
              popupMenuTheme: PopupMenuThemeData(color: p.surface)),
          outlineInk: p.ink,
          outlineSide: p.lineStrong);
      _darkFor = t;
    }
    return _darkData!;
  }

  static ThemeData dataFor(Brightness b) => b == Brightness.dark ? darkData : DolphinLight.data;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final p = DolphinTechPalette.of(b);
    return DolphinFontScale(
      scale: DolphinTheme.of(b).fontScale,
      child: Theme(
        data: dataFor(b),
        child: paint
            ? Material(color: p.ground, child: child)
            : Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// DD-53: «ظاهر» in the technician header: follow Windows (default), light or dark. The choice is upstream's `theme`
/// option, so the session windows follow it too.
class DolphinThemeSwitch extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  const DolphinThemeSwitch({super.key, required this.mode, required this.onChanged});

  static IconData iconOf(ThemeMode m) => switch (m) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    return PopupMenuButton<ThemeMode>(
      tooltip: 'ظاهر: ${themeModeLabel(mode)}',
      initialValue: mode,
      color: p.surface,
      onSelected: onChanged,
      icon: Icon(iconOf(mode), size: 18, color: p.muted),
      itemBuilder: (_) => [
        for (final m in const [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
          PopupMenuItem<ThemeMode>(
            value: m,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(children: [
                Icon(iconOf(m), size: 18, color: m == mode ? p.accent : p.muted),
                const SizedBox(width: 8),
                Text(themeModeLabel(m),
                    style: TextStyle(color: p.ink, fontWeight: m == mode ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
          ),
      ],
    );
  }
}
