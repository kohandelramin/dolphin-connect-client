/// Plan 18 Phase 6 (DD-31, owner 2026-11-13: yes, off by default): «صدای رایانه‌ی مشتری» on the technician's toolbar.
/// Pure rules and texts, so they are tested; session_toolbar.dart draws the button, session_toolbar_hook.dart wires it.
///
/// Every session starts with the sound off (src/client.rs, `LoginConfigHandler::initialize`); the button turns
/// upstream's own session toggle (`disable-audio`) off and on, so sound costs traffic only while the technician wants
/// it. The organization's `remote-sound` switch is enforced on the customer's PC, which sends no sound while it is
/// hidden and says so at login ([kDolphinSoundOffered]); the technician app has no heartbeat and never sees switches.

/// Upstream's session toggle: true while the customer's sound is off.
const kDolphinSoundToggle = 'disable-audio';

/// `platform_additions` key (src/dolphin_system_core.rs PLATFORM_SOUND_OFFERED): false when the customer's
/// organization hides the sound. Absent from an older customer app, which sends sound as upstream does.
const kDolphinSoundOffered = 'dolphin_sound_offered';

enum DolphinSound {
  /// The technician hears the customer's PC.
  on,

  /// Sound is off (every session starts here).
  off,

  /// The customer's organization does not offer it (`remote-sound` hidden in the portal).
  notOffered,

  /// The customer turned «صدا» off in their own connection window (upstream's audio permission).
  closedByCustomer,
}

/// The button's state. [peerOffers] and [audioPermission] are null while the customer's app said nothing about them.
DolphinSound soundState({required bool? peerOffers, required bool? audioPermission, required bool muted}) {
  if (peerOffers == false) return DolphinSound.notOffered;
  if (audioPermission == false) return DolphinSound.closedByCustomer;
  return muted ? DolphinSound.off : DolphinSound.on;
}

/// Only on and off can be pressed; the other two are shown dimmed with their reason.
bool soundCanToggle(DolphinSound s) => s == DolphinSound.on || s == DolphinSound.off;

class DolphinSoundText {
  static const button = 'صدای رایانه‌ی مشتری';
  static const notOffered = 'صدای رایانه‌ی مشتری: برای این سازمان بسته است';
  static const closedByCustomer = 'صدای رایانه‌ی مشتری: مشتری صدا را بسته است';
}

/// The tooltip for a state that cannot be pressed; null for on and off (the button adds «روشن» or «خاموش» itself).
String? soundReason(DolphinSound s) => switch (s) {
      DolphinSound.notOffered => DolphinSoundText.notOffered,
      DolphinSound.closedByCustomer => DolphinSoundText.closedByCustomer,
      _ => null,
    };
