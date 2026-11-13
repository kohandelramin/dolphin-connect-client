import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme_tokens.dart';

export 'theme_tokens.dart' show DolphinTheme, DolphinThemeTokens, DolphinThemeSet, applyThemeOverrides, kDolphinDemoRed;

/// Dolphin's palette, as the customer screens name it: each colour reads the light tokens in use
/// ([DolphinTheme.light], theme_tokens.dart), so a theme the portal pushes reaches every view. With the built-in tokens
/// every value is the portal's own (app/src/app/globals.css), as before Plan 19. Getters, not constants: a view that
/// uses one cannot be `const` (the colour may change while the app runs).
class DolphinColors {
  DolphinColors._();
  static DolphinThemeTokens get _t => DolphinTheme.light;

  static Color get azure => _t.primary; // the one primary blue (D20) as a fill; white on it 5.45:1
  static Color get azureText => _t.primaryText; // the blue as text or an icon; 4.97:1 on azureSoft
  static Color get azureSoft => _t.surfaceAlt;
  static Color get azureTint => _t.primaryTint;
  static Color get aqua => _t.accent; // fills and icons only (3.74:1 on white)
  static Color get aquaText => _t.success; // small aqua text (5.47:1 on white, 4.91:1 on aquaSoft)
  static Color get aquaSoft => _t.accentSoft;
  static Color get ink => _t.text;
  static Color get msgSuccess => _t.success; // message-box success icon on a white dialog 5.47:1 (upstream #32bea6 was 2.3:1)
  static Color get msgError => _t.errorIcon; // message-box error icon on a white dialog 4.73:1 (upstream #E04F5F was 3.9:1)
  static Color get danger => _t.dangerFill;
  static Color get dangerText => _t.danger;
  static Color get dangerSoft => _t.dangerSoft;
  static Color get amberText => _t.warning; // the portal's amber text, for notices (6.59:1 on amberSoft)
  static Color get amberSoft => _t.warningSoft;
  static Color get fieldEdge => _t.offlineDot; // the portal's «در دسترس نیست» dot (StatusDot); a fill, never text
  static Color get ground => _t.background;
  static Color get surface => _t.surface;
  static Color get muted => _t.textMuted;
  static Color get line => _t.line;
  static Color get lineStrong => _t.lineStrong;
}

/// The portal's radii: fields 10, controls 12, cards 18 (tokens `radius` and `radiusLarge`; fields one step less).
class DolphinRadii {
  DolphinRadii._();
  static double get field => DolphinTheme.light.radiusField;
  static double get control => DolphinTheme.light.radius;
  static double get card => DolphinTheme.light.radiusLarge;
}

/// Embedded in the app (assets/fonts), so it renders the same on every Windows.
const kDolphinFont = 'Vazirmatn';

/// Dolphin's look over the upstream theme: Vazirmatn everywhere, azure and aqua as the brand colours (the tokens of
/// the base theme's brightness).
ThemeData dolphinTheme(ThemeData base) {
  final t = DolphinTheme.of(base.brightness);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(primary: t.primary, secondary: t.accent, error: t.dangerFill),
    textTheme: base.textTheme.apply(fontFamily: kDolphinFont),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kDolphinFont),
  );
}

/// One button system for every Dolphin view (DR-6, AUI-6): 44 px tall, the control radius, bold labels. Filled is the
/// one main action, outlined the others, text buttons for quiet links. Views set only colours, never sizes or radii.
/// [outlineInk] and [outlineSide] are the outlined button's text and border: the light ones by default; the
/// technician app's dark palette passes its own (DD-53, tech_theme.dart).
ThemeData dolphinButtons(ThemeData t, {Color? outlineInk, Color? outlineSide}) {
  final tokens = DolphinTheme.of(t.brightness);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(tokens.radius)));
  const size = Size(64, 44);
  const padding = EdgeInsets.symmetric(horizontal: 16);
  const label = TextStyle(fontFamily: kDolphinFont, fontWeight: FontWeight.w700, fontSize: 14);
  return t.copyWith(
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape, textStyle: label, backgroundColor: tokens.primary,
            foregroundColor: tokens.onPrimary)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape, textStyle: label, elevation: 0,
            backgroundColor: tokens.primary, foregroundColor: tokens.onPrimary)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape, textStyle: label,
            foregroundColor: outlineInk ?? tokens.text, side: BorderSide(color: outlineSide ?? tokens.lineStrong))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: size, padding: padding, shape: shape, textStyle: label)),
  );
}

/// The one theme of all our customer screens, whatever Windows' theme is (DR-1, owner 2026-10-28): light, as the
/// portal. The technician app has a light and a dark one (DD-53, tech_theme.dart).
/// Upstream's app follows the system theme, and in dark mode its text, scaffold and chip colours leaked into our
/// views (white on white, 1.24:1 chips). Every Dolphin view wraps itself in this, so no view depends on the app theme.
/// [paint] fills the view with the ground colour; false for overlays (permission strip, call status) that sit over
/// something else and only need the light text defaults.
class DolphinLight extends StatelessWidget {
  final Widget child;
  final bool paint;
  const DolphinLight({super.key, required this.child, this.paint = true});

  static DolphinThemeTokens? _dataFor;
  static ThemeData? _data;

  /// Built once per token set (the built-in one, or the portal's while it is in use).
  static ThemeData get data {
    final t = DolphinTheme.light;
    if (!identical(t, _dataFor) || _data == null) {
      _data = dolphinButtons(dolphinTheme(ThemeData(brightness: Brightness.light, useMaterial3: false)));
      _dataFor = t;
    }
    return _data!;
  }

  @override
  Widget build(BuildContext context) => DolphinFontScale(
        scale: DolphinTheme.light.fontScale,
        child: Theme(
          data: data,
          child: paint
              ? Material(color: DolphinColors.ground, child: child)
              : Material(type: MaterialType.transparency, child: child),
        ),
      );
}

/// The `fontScale` token: every text below grows or shrinks by it, on top of Windows' own text scaling. 1 (the
/// built-in) changes nothing.
class DolphinFontScale extends StatelessWidget {
  final double scale;
  final Widget child;
  const DolphinFontScale({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return child;
    return MediaQuery(
        data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(14) / 14 * scale)), child: child);
  }
}

/// A pushed theme reaches views that read [DolphinColors] in their build: when the tokens change, every widget in
/// the app builds again once (no state is lost; nothing is remounted). Installed once by theme_option.dart.
void dolphinRebuildOnThemeChange() {
  if (_rebuildInstalled) return;
  _rebuildInstalled = true;
  DolphinTheme.active.addListener(() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    void markAll() => WidgetsBinding.instance.rootElement?.visitChildren(mark);
    // A theme applied from a widget's initState arrives while the tree builds: mark it after this frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      markAll();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => markAll());
    }
  });
}

bool _rebuildInstalled = false;
