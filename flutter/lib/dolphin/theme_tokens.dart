import 'dart:convert';

import 'package:flutter/material.dart';

/// Plan 19 (owner 2026-11-14: "apps design should be updateable through its theme"): every colour, radius and font
/// scale of both apps comes from one token set. The built-in tokens below are today's look (the portal's tokens,
/// app/src/app/globals.css, and the technician's dark palette of DD-53); the portal can push overrides as
/// `dolphin-theme` = `{"v": 1, "light": {...}, "dark": {...}}` (the customer app reads it from the heartbeat's options,
/// the technician app will get it from the app API's `/config`), so the look changes without an app build.
///
/// Pure: no bridge, no I/O, so the rules are tested alone (test/dolphin/theme_tokens_test.dart).
const kDolphinThemeOption = 'dolphin-theme';

/// The token names the portal may set, exactly as in the plan's contract.
const kDolphinColorTokens = [
  'primary',
  'primaryText',
  'accent',
  'background',
  'surface',
  'surfaceAlt',
  'line',
  'text',
  'textMuted',
  'success',
  'warning',
  'danger',
];
const kDolphinNumberTokens = ['radius', 'radiusLarge', 'fontScale'];

/// Bounds for the numbers (inclusive). Outside them the whole override is ignored.
const Map<String, (double, double)> kDolphinNumberBounds = {
  'radius': (0, 24),
  'radiusLarge': (0, 32),
  'fontScale': (0.85, 1.3),
};

/// One brightness's tokens.
///   primary      the brand blue as a fill (buttons, bars); white text sits on it
///   primaryText  the brand blue as text or an icon on background, surface and surfaceAlt
///   accent       aqua as a fill or icon (never small text)
///   background   behind everything (the window's ground)
///   surface      cards, dialogs, the header
///   surfaceAlt   a quiet tinted fill (chips, selected rows, soft notices); primaryText reads on it
///   line         hairlines
///   text         body text
///   textMuted    secondary text
///   success / warning / danger   status colours as text on surface
///   radius       controls (buttons, fields one step less); radiusLarge cards and dialogs
///   fontScale    multiplies every text size (1 = as designed)
///
/// Colours the views need beyond these (soft status fills, the strong field border, the danger fill) are derived:
/// with the built-in tokens they are exactly today's constants; when an override changes a token they follow it.
@immutable
class DolphinThemeTokens {
  final Brightness brightness;
  final Color primary;
  final Color primaryText;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color line;
  final Color text;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final double radius;
  final double radiusLarge;
  final double fontScale;

  // Derived (not tokens). Built-in values are today's; merged ones follow the tokens they come from.
  final Color primaryTint;
  final Color accentSoft;
  final Color warningSoft;
  final Color dangerFill;
  final Color dangerSoft;
  final Color lineStrong;
  final Color errorIcon;
  final Color offlineDot;

  const DolphinThemeTokens._({
    required this.brightness,
    required this.primary,
    required this.primaryText,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.line,
    required this.text,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.radius,
    required this.radiusLarge,
    required this.fontScale,
    required this.primaryTint,
    required this.accentSoft,
    required this.warningSoft,
    required this.dangerFill,
    required this.dangerSoft,
    required this.lineStrong,
    required this.errorIcon,
    required this.offlineDot,
  });

  /// Today's light look: the portal's tokens. White on [primary] 5.45:1, [primaryText] on [surfaceAlt] 4.97:1.
  static const builtInLight = DolphinThemeTokens._(
    brightness: Brightness.light,
    primary: Color(0xFF1462E0),
    primaryText: Color(0xFF1462E0),
    accent: Color(0xFF0D9488),
    background: Color(0xFFF6F9FF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEF5FF),
    line: Color(0xFFE2E9F3),
    text: Color(0xFF0B1829),
    textMuted: Color(0xFF52637A),
    success: Color(0xFF0F766E),
    warning: Color(0xFF92400E),
    danger: Color(0xFFBE123C),
    radius: 12,
    radiusLarge: 18,
    fontScale: 1,
    primaryTint: Color(0xFFD9E8FF),
    accentSoft: Color(0xFFE6F6F4),
    warningSoft: Color(0xFFFEF6E0),
    dangerFill: Color(0xFFE11D48),
    dangerSoft: Color(0xFFFFF0F3),
    lineStrong: Color(0xFFC8D6E8),
    errorIcon: Color(0xFFD03C4E),
    offlineDot: Color(0xFF728AA6),
  );

  /// Today's dark look (the technician app, DD-53): the website's ink ground with azure and aqua lifted.
  static const builtInDark = DolphinThemeTokens._(
    brightness: Brightness.dark,
    primary: Color(0xFF1462E0),
    primaryText: Color(0xFF8AB8FF),
    accent: Color(0xFF0D9488),
    background: Color(0xFF0B1829),
    surface: Color(0xFF13233A),
    surfaceAlt: Color(0xFF1B355C),
    line: Color(0xFF22344D),
    text: Color(0xFFE8EEF7),
    textMuted: Color(0xFFA3B3C7),
    success: Color(0xFF5EEAD4),
    warning: Color(0xFFFCD34D),
    danger: Color(0xFFFF9FB2),
    radius: 12,
    radiusLarge: 18,
    fontScale: 1,
    primaryTint: Color(0xFF1B355C),
    accentSoft: Color(0xFF123B3A),
    warningSoft: Color(0xFF3A2E12),
    dangerFill: Color(0xFFE11D48),
    dangerSoft: Color(0xFF3B1A24),
    lineStrong: Color(0xFF4A6080),
    errorIcon: Color(0xFFFF9FB2),
    offlineDot: Color(0xFF728AA6),
  );

  static DolphinThemeTokens builtIn(Brightness b) => b == Brightness.dark ? builtInDark : builtInLight;

  /// Text and icons on a [primary] fill.
  Color get onPrimary => Colors.white;

  /// Fields: one step less than controls (10 with the built-in 12).
  double get radiusField => radius >= 2 ? radius - 2 : 0;

  /// Small chips (the technician's toolbar): 8 with the built-in 12; the screen tiles 6.
  double get radiusSmall => radius * 2 / 3;
  double get radiusTiny => radius / 2;

  Color color(String name) => switch (name) {
        'primary' => primary,
        'primaryText' => primaryText,
        'accent' => accent,
        'background' => background,
        'surface' => surface,
        'surfaceAlt' => surfaceAlt,
        'line' => line,
        'text' => text,
        'textMuted' => textMuted,
        'success' => success,
        'warning' => warning,
        'danger' => danger,
        _ => throw ArgumentError.value(name, 'name', 'not a colour token'),
      };

  double number(String name) => switch (name) {
        'radius' => radius,
        'radiusLarge' => radiusLarge,
        'fontScale' => fontScale,
        _ => throw ArgumentError.value(name, 'name', 'not a number token'),
      };

  /// These tokens with [colors] and [numbers] put over them (already validated). Derived colours follow the tokens
  /// they come from only when one of those changed, so the built-in look stays exact.
  DolphinThemeTokens merged(Map<String, Color> colors, Map<String, double> numbers) {
    Color c(String n) => colors[n] ?? color(n);
    double d(String n) => numbers[n] ?? number(n);
    bool changed(List<String> names) => names.any((n) => colors.containsKey(n) && colors[n] != color(n));
    Color mix(Color from, Color to, double t) => Color.lerp(from, to, t)!;
    final surface = c('surface'), primary = c('primary'), accent = c('accent');
    final warning = c('warning'), danger = c('danger'), line = c('line'), muted = c('textMuted');
    return DolphinThemeTokens._(
      brightness: brightness,
      primary: primary,
      primaryText: c('primaryText'),
      accent: accent,
      background: c('background'),
      surface: surface,
      surfaceAlt: c('surfaceAlt'),
      line: line,
      text: c('text'),
      textMuted: muted,
      success: c('success'),
      warning: warning,
      danger: danger,
      radius: d('radius'),
      radiusLarge: d('radiusLarge'),
      fontScale: d('fontScale'),
      primaryTint: changed(['primary', 'surface']) ? mix(surface, primary, 0.16) : primaryTint,
      accentSoft: changed(['accent', 'surface']) ? mix(surface, accent, 0.1) : accentSoft,
      warningSoft: changed(['warning', 'surface']) ? mix(surface, warning, 0.1) : warningSoft,
      dangerFill: changed(['danger']) ? danger : dangerFill,
      dangerSoft: changed(['danger', 'surface']) ? mix(surface, danger, 0.08) : dangerSoft,
      lineStrong: changed(['line', 'textMuted']) ? mix(line, muted, 0.3) : lineStrong,
      errorIcon: changed(['danger']) ? danger : errorIcon,
      offlineDot: changed(['textMuted']) ? muted : offlineDot,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DolphinThemeTokens &&
      other.brightness == brightness &&
      kDolphinColorTokens.every((n) => other.color(n) == color(n)) &&
      kDolphinNumberTokens.every((n) => other.number(n) == number(n)) &&
      other.primaryTint == primaryTint &&
      other.accentSoft == accentSoft &&
      other.warningSoft == warningSoft &&
      other.dangerFill == dangerFill &&
      other.dangerSoft == dangerSoft &&
      other.lineStrong == lineStrong &&
      other.errorIcon == errorIcon &&
      other.offlineDot == offlineDot;

  @override
  int get hashCode => Object.hashAll([
        brightness,
        for (final n in kDolphinColorTokens) color(n),
        for (final n in kDolphinNumberTokens) number(n),
      ]);
}

/// The light and the dark tokens of one theme.
@immutable
class DolphinThemeSet {
  final DolphinThemeTokens light;
  final DolphinThemeTokens dark;
  const DolphinThemeSet(this.light, this.dark);

  static const builtIn = DolphinThemeSet(DolphinThemeTokens.builtInLight, DolphinThemeTokens.builtInDark);

  DolphinThemeTokens of(Brightness b) => b == Brightness.dark ? dark : light;

  @override
  bool operator ==(Object other) => other is DolphinThemeSet && other.light == light && other.dark == dark;

  @override
  int get hashCode => Object.hash(light, dark);
}

/// WCAG 2.x contrast ratio of two opaque colours (the same formula as test/dolphin/contrast.dart, which uses this).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// AA for normal text.
const kDolphinMinContrast = 4.5;

/// The text pairs every view relies on. An override where any of them is below AA is refused as a whole.
List<(String, Color, Color)> contrastPairs(DolphinThemeTokens t) => [
      ('text on background', t.text, t.background),
      ('text on surface', t.text, t.surface),
      ('textMuted on background', t.textMuted, t.background),
      ('textMuted on surface', t.textMuted, t.surface),
      ('primaryText on background', t.primaryText, t.background),
      ('primaryText on surface', t.primaryText, t.surface),
      ('primaryText on surfaceAlt', t.primaryText, t.surfaceAlt),
      ('white on primary', t.onPrimary, t.primary),
      ('success on surface', t.success, t.surface),
      ('warning on surface', t.warning, t.surface),
      ('danger on surface', t.danger, t.surface),
    ];

/// The pairs below AA, by name; empty when every pair reads.
List<String> contrastProblems(DolphinThemeTokens t) => [
      for (final (name, fg, bg) in contrastPairs(t))
        if (contrastRatio(fg, bg) < kDolphinMinContrast) name,
    ];

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// One brightness's overrides, or null when anything in it is malformed (a colour that is not `#rrggbb`, a number
/// out of bounds or not a number). Unknown keys are ignored.
DolphinThemeTokens? _overrideOne(DolphinThemeTokens base, Object? raw) {
  if (raw == null) return base;
  if (raw is! Map) return null;
  final colors = <String, Color>{};
  final numbers = <String, double>{};
  for (final entry in raw.entries) {
    final key = entry.key, value = entry.value;
    if (kDolphinColorTokens.contains(key)) {
      if (value is! String || !_hex.hasMatch(value)) return null;
      colors[key as String] = Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
    } else if (kDolphinNumberTokens.contains(key)) {
      if (value is! num || value.isNaN) return null;
      final (lo, hi) = kDolphinNumberBounds[key]!;
      final v = value.toDouble();
      if (v < lo || v > hi) return null;
      numbers[key as String] = v;
    }
  }
  return base.merged(colors, numbers);
}

/// The theme the pushed value asks for, or null when it must be ignored as a whole: not JSON, not an object, not
/// version 1, a malformed token, or a result whose text would not read (below AA). Unknown keys are ignored. Light
/// and dark are each optional; a missing one keeps the built-in tokens.
DolphinThemeSet? parseThemeOverrides(String raw) {
  final Object? data;
  try {
    data = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (data is! Map || data['v'] != 1) return null;
  final light = _overrideOne(DolphinThemeTokens.builtInLight, data['light']);
  final dark = _overrideOne(DolphinThemeTokens.builtInDark, data['dark']);
  if (light == null || dark == null) return null;
  if (contrastProblems(light).isNotEmpty || contrastProblems(dark).isNotEmpty) return null;
  return DolphinThemeSet(light, dark);
}

/// The tokens in use. Views read them through [DolphinColors] / [DolphinTechPalette] (theme.dart, tech_theme.dart).
class DolphinTheme {
  DolphinTheme._();

  static final ValueNotifier<DolphinThemeSet> active = ValueNotifier(DolphinThemeSet.builtIn);

  static DolphinThemeTokens get light => active.value.light;
  static DolphinThemeTokens get dark => active.value.dark;
  static DolphinThemeTokens of(Brightness b) => active.value.of(b);
}

/// What [applyThemeOverrides] did.
enum ThemeOverrideResult {
  /// The value was empty or "-": the built-in tokens are in use.
  builtIn,

  /// The override is in use.
  applied,

  /// The value was malformed or failed the contrast check: ignored as a whole, the built-in tokens are in use.
  ignored,
}

/// Puts a pushed theme in use: the customer app calls it with the `dolphin-theme` option (theme_option.dart), the
/// technician app (wave 2) with the app API's `/config` `theme`. Accepts the JSON text or an already decoded map.
/// Empty, "-" or null means the portal set no theme. A malformed or unreadable value never leaves a half-applied look:
/// the built-in tokens stay. Listeners of [DolphinTheme.active] hear only real changes.
ThemeOverrideResult applyThemeOverrides(Object? json) {
  final String raw;
  if (json == null) {
    raw = '';
  } else if (json is String) {
    raw = json.trim();
  } else {
    try {
      raw = jsonEncode(json);
    } catch (_) {
      DolphinTheme.active.value = DolphinThemeSet.builtIn;
      return ThemeOverrideResult.ignored;
    }
  }
  if (raw.isEmpty || raw == '-') {
    DolphinTheme.active.value = DolphinThemeSet.builtIn;
    return ThemeOverrideResult.builtIn;
  }
  final set = parseThemeOverrides(raw);
  DolphinTheme.active.value = set ?? DolphinThemeSet.builtIn;
  return set == null ? ThemeOverrideResult.ignored : ThemeOverrideResult.applied;
}
