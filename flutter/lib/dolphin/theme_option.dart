import '../models/platform_model.dart';
import 'theme.dart';
import 'theme_tokens.dart';

/// Plan 19: the customer app takes the portal's theme from the heartbeat. The portal pushes `dolphin-theme` with the
/// other options (like `dolphin-switches`); the main window reads it every 2 s (home.dart) and puts it in use when it
/// changes. The session window (`--cm`, its own process) has no option sync of its own, so the main window keeps the
/// value it applied as a local option of this Windows account, and the session window reads that when it opens.
/// The technician app has no heartbeat: wave 2 calls [applyThemeOverrides] with the app API's `/config` theme.
const kDolphinThemeAppliedLocal = 'dolphin-theme-applied';

String? _lastRaw;

/// What changed, for the caller: true when the value differs from the last one read (applied or not).
bool syncThemeFromPortal() {
  final raw = bind.mainGetOptionSync(key: kDolphinThemeOption);
  if (!themeValueChanged(_lastRaw, raw)) return false;
  _lastRaw = raw;
  dolphinRebuildOnThemeChange();
  applyThemeOverrides(raw);
  // Only a value this app accepted is handed to the session window; anything else hands it the built-in look.
  final kept = DolphinTheme.active.value == DolphinThemeSet.builtIn ? '' : raw;
  if (bind.mainGetLocalOption(key: kDolphinThemeAppliedLocal) != kept) {
    bind.mainSetLocalOption(key: kDolphinThemeAppliedLocal, value: kept);
  }
  return true;
}

/// The session window: the theme the main window last applied.
void themeFromMainWindow() {
  final raw = bind.mainGetLocalOption(key: kDolphinThemeAppliedLocal);
  if (!themeValueChanged(_lastRaw, raw)) return;
  _lastRaw = raw;
  dolphinRebuildOnThemeChange();
  applyThemeOverrides(raw);
}

/// The first read always counts; afterwards only a different text does (a JSON parse every 2 s would be waste).
bool themeValueChanged(String? last, String now) => last == null || last != now;
