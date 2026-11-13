import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme_tokens.dart';

export 'theme_tokens.dart' show DolphinTheme, DolphinThemeTokens, DolphinThemeSet, applyThemeOverrides, kDolphinDemoRed;

/// Plan 19 (C5): the customer chooses how the customer app looks, «مثل ویندوز», «روشن» or «تیره». Kept as a local
/// option of this Windows account (not pushed by the portal); the session window reads it when it opens.
const kDolphinThemeChoiceLocal = 'dolphin-theme-choice';

enum DolphinThemeChoice { system, light, dark }

/// The stored value; anything unknown (or nothing yet) is «مثل ویندوز», the approved default (design C5).
DolphinThemeChoice themeChoiceFrom(String raw) => switch (raw.trim()) {
      'light' => DolphinThemeChoice.light,
      'dark' => DolphinThemeChoice.dark,
      _ => DolphinThemeChoice.system,
    };

/// What to store: '' for «مثل ویندوز», so the default needs no write.
String themeChoiceValue(DolphinThemeChoice c) => c == DolphinThemeChoice.system ? '' : c.name;

/// The brightness the customer screens draw with.
Brightness brightnessFor(DolphinThemeChoice c, Brightness platform) => switch (c) {
      DolphinThemeChoice.system => platform,
      DolphinThemeChoice.light => Brightness.light,
      DolphinThemeChoice.dark => Brightness.dark,
    };

const kThemeChoiceLabels = {
  DolphinThemeChoice.system: 'مثل ویندوز',
  DolphinThemeChoice.light: 'روشن',
  DolphinThemeChoice.dark: 'تیره',
};

/// The brightness of the customer screens ([DolphinColors], [DolphinLight]). Light until the customer app applies the
/// customer's choice ([apply], theme_option.dart); the technician app never does, so the few shared views it draws
/// with these colours stay exactly as before (its own look is tech_theme.dart).
class DolphinCustomerTheme {
  DolphinCustomerTheme._();

  static final ValueNotifier<Brightness> brightness = ValueNotifier(Brightness.light);
  static DolphinThemeChoice _choice = DolphinThemeChoice.light;
  static DolphinThemeChoice get choice => _choice;
  static _PlatformBrightnessWatch? _watch;

  /// Puts [c] in use; «مثل ویندوز» then follows Windows when its theme changes. [platform] is for tests.
  static void apply(DolphinThemeChoice c, {Brightness? platform}) {
    _choice = c;
    if (platform == null && _watch == null) {
      try {
        final watch = _PlatformBrightnessWatch();
        WidgetsBinding.instance.addObserver(watch);
        _watch = watch;
      } catch (_) {
        // No binding yet: nothing to follow.
      }
      dolphinRebuildOnThemeChange();
    }
    brightness.value = brightnessFor(c, platform ?? _platform());
  }

  static Brightness _platform() {
    try {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    } catch (_) {
      return Brightness.light;
    }
  }

  /// Back to the default before any choice was applied (tests, previews).
  static void reset() {
    _choice = DolphinThemeChoice.light;
    brightness.value = Brightness.light;
  }
}

class _PlatformBrightnessWatch with WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() {
    if (DolphinCustomerTheme._choice != DolphinThemeChoice.system) return;
    DolphinCustomerTheme.brightness.value = DolphinCustomerTheme._platform();
  }
}

/// The tokens the customer screens draw with now: the portal's (or built-in) tokens of the customer's brightness.
DolphinThemeTokens get dolphinCustomerTokens => DolphinTheme.of(DolphinCustomerTheme.brightness.value);

/// Dolphin's palette, as the customer screens name it: each colour reads the tokens in use for the customer's
/// brightness ([dolphinCustomerTokens], theme_tokens.dart), so a theme the portal pushes reaches every view and the
/// customer's «روشن» and «تیره» (C5) both read. With the built-in light tokens every value is the portal's own
/// (app/src/app/globals.css), as before Plan 19. Getters, not constants: a view that uses one cannot be `const` (the
/// colour may change while the app runs).
class DolphinColors {
  DolphinColors._();
  static DolphinThemeTokens get _t => dolphinCustomerTokens;

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

  /// Text and icons on [azure], [danger] and [accentFill] (white).
  static Color get onFill => _t.onPrimary;

  /// Aqua as a fill under white text (C2 «پذیرفتن»): the accent token darkened just enough for white to reach AA (the
  /// accent itself is 3.74:1 with white), so a pushed accent still gives a readable button.
  static Color get accentFill => readableFill(_t.accent, _t.onPrimary);

  /// C3: the coloured frame around the customer's screen during a session (session_frame.dart).
  static Color get frame => _t.dangerFill;
}

/// [fill] darkened in small steps until [on] reaches AA on it (black at worst).
Color readableFill(Color fill, Color on) {
  for (var i = 0; i <= 20; i++) {
    final c = Color.lerp(fill, Colors.black, i / 20)!;
    if (contrastRatio(on, c) >= kDolphinMinContrast) return c;
  }
  return Colors.black;
}

/// The portal's radii: fields 10, controls 12, cards 18 (tokens `radius` and `radiusLarge`; fields one step less).
class DolphinRadii {
  DolphinRadii._();
  static double get field => dolphinCustomerTokens.radiusField;
  static double get control => dolphinCustomerTokens.radius;
  static double get card => dolphinCustomerTokens.radiusLarge;
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
ThemeData dolphinButtons(ThemeData t, {Color? outlineInk, Color? outlineSide, Color? textInk}) {
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
        style: TextButton.styleFrom(
            minimumSize: size, padding: padding, shape: shape, textStyle: label, foregroundColor: textInk)),
  );
}

/// The one theme of all our customer screens, whatever upstream's app theme is (DR-1, owner 2026-10-28). Since Plan 19
/// (C5) its brightness is the customer's choice ([DolphinCustomerTheme]: light until the customer app applies it, and
/// always light in the technician app, which has its own light and dark, DD-53, tech_theme.dart). The name stays from
/// DR-1, when it was always light.
/// Upstream's app follows the system theme, and in dark mode its text, scaffold and chip colours leaked into our
/// views (white on white, 1.24:1 chips). Every Dolphin view wraps itself in this, so no view depends on the app theme.
/// [paint] fills the view with the ground colour; false for overlays (permission strip, call status) that sit over
/// something else and only need the text defaults.
class DolphinLight extends StatelessWidget {
  final Widget child;
  final bool paint;
  const DolphinLight({super.key, required this.child, this.paint = true});

  static DolphinThemeTokens? _dataFor;
  static ThemeData? _data;

  /// Built once per token set (the built-in light or dark one, or the portal's while it is in use).
  static ThemeData get data {
    final t = dolphinCustomerTokens;
    if (!identical(t, _dataFor) || _data == null) {
      final base = dolphinTheme(ThemeData(brightness: t.brightness, useMaterial3: false));
      _data = dolphinButtons(base.copyWith(
        // The ground, cards, dialogs and text of the tokens, so nothing falls back to Material's own greys.
        scaffoldBackgroundColor: t.background,
        canvasColor: t.surface,
        cardColor: t.surface,
        dialogBackgroundColor: t.surface,
        dividerColor: t.line,
        colorScheme: base.colorScheme.copyWith(surface: t.surface, onSurface: t.text, onPrimary: t.onPrimary),
        textTheme: base.textTheme.apply(bodyColor: t.text, displayColor: t.text),
        iconTheme: IconThemeData(color: t.textMuted),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.onPrimary : t.surface),
          trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.primary : t.offlineDot),
        ),
      ), textInk: t.primaryText);
      _dataFor = t;
    }
    return _data!;
  }

  @override
  Widget build(BuildContext context) => DolphinFontScale(
        scale: dolphinCustomerTokens.fontScale,
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

/// A pushed theme, or the customer's light or dark (C5), reaches views that read [DolphinColors] in their build: when
/// either changes, every widget in the app builds again once (no state is lost; nothing is remounted). Installed once
/// by theme_option.dart and [DolphinCustomerTheme.apply].
void dolphinRebuildOnThemeChange() {
  if (_rebuildInstalled) return;
  _rebuildInstalled = true;
  void rebuildAll() {
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
  }

  DolphinTheme.active.addListener(rebuildAll);
  DolphinCustomerTheme.brightness.addListener(rebuildAll);
}

bool _rebuildInstalled = false;
