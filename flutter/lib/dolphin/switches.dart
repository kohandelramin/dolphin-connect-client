import 'dart:convert';

/// Pushed by the portal (app/src/lib/switches.ts, DD-4): our own feature switches as one JSON object
/// `{"key": "hidden" | "available" | "forced"}`, resolved for this PC's organization.
///   hidden     the feature is off and its control is not shown;
///   available  the control is shown and the person at the PC decides (the feature's own default applies);
///   forced     the feature is on and its control cannot turn it off.
const kDolphinSwitchesOption = 'dolphin-switches';

enum SwitchMode { hidden, available, forced }

/// Keys the portal knows today (keep in step with FEATURE_SWITCHES in the portal).
class DolphinSwitch {
  static const directRoute = 'direct-route';
  static const shareToggle = 'share-toggle';
  static const stayInTray = 'stay-in-tray';
  static const receiveFolder = 'receive-folder';
  static const diagnosticsUpload = 'diagnostics-upload';
  static const remotePrinter = 'remote-printer';
  static const wakeOnLan = 'wake-on-lan';
  static const safeMode = 'safe-mode';
  static const remoteSound = 'remote-sound';
}

/// Defaults when the portal has not said anything yet (a PC never linked, or an app older than the portal's list).
/// They match the portal's defaults, so a new PC behaves the same before and after its first heartbeat.
const Map<String, SwitchMode> kSwitchDefaults = {
  DolphinSwitch.directRoute: SwitchMode.forced,
  DolphinSwitch.shareToggle: SwitchMode.available,
  DolphinSwitch.stayInTray: SwitchMode.available,
  DolphinSwitch.receiveFolder: SwitchMode.available,
  DolphinSwitch.diagnosticsUpload: SwitchMode.available,
  DolphinSwitch.remotePrinter: SwitchMode.hidden,
  DolphinSwitch.wakeOnLan: SwitchMode.hidden,
  DolphinSwitch.safeMode: SwitchMode.hidden,
  DolphinSwitch.remoteSound: SwitchMode.available,
};

class DolphinSwitches {
  final Map<String, SwitchMode> _modes;
  const DolphinSwitches(this._modes);

  /// The pushed option; anything unexpected (missing, "-", bad JSON, unknown modes) falls back to the defaults, key
  /// by key, so one bad value cannot switch other features.
  factory DolphinSwitches.parse(String raw) {
    final modes = Map<String, SwitchMode>.of(kSwitchDefaults);
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        data.forEach((k, v) {
          if (k is! String || v is! String) return;
          for (final m in SwitchMode.values) {
            if (m.name == v) modes[k] = m;
          }
        });
      }
    } catch (_) {}
    return DolphinSwitches(modes);
  }

  /// Unknown keys are hidden: an app never shows a feature the portal does not know.
  SwitchMode mode(String key) => _modes[key] ?? SwitchMode.hidden;
  bool shown(String key) => mode(key) != SwitchMode.hidden;
  bool forced(String key) => mode(key) == SwitchMode.forced;

  /// Whether the feature is on, given the person's own choice (null: they have not chosen; `defaultOn` applies).
  bool on(String key, {bool? chosen, bool defaultOn = true}) {
    switch (mode(key)) {
      case SwitchMode.hidden:
        return false;
      case SwitchMode.forced:
        return true;
      case SwitchMode.available:
        return chosen ?? defaultOn;
    }
  }
}
