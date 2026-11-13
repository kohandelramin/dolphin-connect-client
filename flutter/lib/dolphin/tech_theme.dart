import 'package:flutter/material.dart';

import 'theme.dart';

/// DD-53: the technician app's colours, light and dark. The customer's screens stay light whatever Windows says (DR-1);
/// the technician, who sits in front of the app all day, chooses: «مثل ویندوز» (the default), «روشن» or «تیره».
/// Every pair a view uses is checked for contrast in test/dolphin/tech_theme_test.dart.
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
  });

  /// The portal's own light tokens (theme.dart).
  static const light = DolphinTechPalette._(
    brightness: Brightness.light,
    ground: DolphinColors.ground,
    surface: Colors.white,
    ink: DolphinColors.ink,
    muted: DolphinColors.muted,
    line: DolphinColors.line,
    lineStrong: DolphinColors.lineStrong,
    accent: DolphinColors.azure,
    accentSoft: DolphinColors.azureSoft,
    okText: DolphinColors.aquaText,
    warnText: DolphinColors.amberText,
    dangerText: DolphinColors.dangerText,
  );

  /// The ink ground of the website, with azure and aqua lifted so they read on it.
  static const dark = DolphinTechPalette._(
    brightness: Brightness.dark,
    ground: Color(0xFF0B1829), // DolphinColors.ink
    surface: Color(0xFF13233A),
    ink: Color(0xFFE8EEF7),
    muted: Color(0xFFA3B3C7),
    line: Color(0xFF22344D),
    lineStrong: Color(0xFF4A6080),
    accent: Color(0xFF8AB8FF),
    accentSoft: Color(0xFF1B355C),
    okText: Color(0xFF5EEAD4),
    warnText: Color(0xFFFCD34D),
    dangerText: Color(0xFFFF9FB2),
  );

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

  static final ThemeData darkData = dolphinButtons(
      dolphinTheme(ThemeData(brightness: Brightness.dark, useMaterial3: false)).copyWith(
          scaffoldBackgroundColor: DolphinTechPalette.dark.ground,
          canvasColor: DolphinTechPalette.dark.surface,
          popupMenuTheme: PopupMenuThemeData(color: DolphinTechPalette.dark.surface)),
      outlineInk: DolphinTechPalette.dark.ink,
      outlineSide: DolphinTechPalette.dark.lineStrong);

  static ThemeData dataFor(Brightness b) => b == Brightness.dark ? darkData : DolphinLight.data;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final p = DolphinTechPalette.of(b);
    return Theme(
      data: dataFor(b),
      child: paint
          ? Material(color: p.ground, child: child)
          : Material(type: MaterialType.transparency, child: child),
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
