import 'dart:math';

import 'digits.dart';

/// Owner decision D23: when a technician's connection drops (a network blip, a VPN going on or off), the technician app
/// tries again by itself, quietly, for about two minutes, instead of an error box. The customer PC takes the session
/// back without a new Accept when the fixed password is on for its organization (D21, src/dolphin_fixed_core.rs), or
/// when the session began with the one-time password (within 2 minutes, `SESSION_TIMEOUT` in
/// src/server/connection.rs). Otherwise the customer sees the accept prompt again. Pure, so it is unit-tested.
/// Hooked into `FfiModel.handleMsgBox` (flutter/lib/models/model.dart, marked `Dolphin Connect`).

const kDolphinReconnectWindow = Duration(minutes: 2);

/// Shown instead of the error while the app retries; [left] is how much of the window remains.
String dolphinReconnectingText(Duration left) {
  final seconds = left.isNegative ? 0 : left.inSeconds;
  return 'ارتباط با رایانه‌ی مشتری قطع شد. در حال اتصال دوباره… (تا ${faDigits('$seconds')} ثانیه‌ی دیگر)';
}

/// A short notice when a retry got the session back (technician app), and the customer window's session badge.
const kDolphinReconnected = 'دوباره وصل شد';

/// Customer window: a session from a technician who was in a live session on this PC less than the window ago is shown
/// as «دوباره وصل شد», so the customer knows it is the same help coming back, not someone new.
bool dolphinResumed(DateTime? lastLive, DateTime now) =>
    lastLive != null && now.difference(lastLive) < kDolphinReconnectWindow;

/// Ends that are on purpose or will not pass by themselves: never retried quietly. The texts are the untranslated keys
/// the Rust side sends (close reasons and connection errors).
const _notTransient = [
  'manually', // «پایان» by the customer, the technician, or the portal's cut ("Closed manually by web console")
  'not allowed',
  'incoming only',
  'mismatch', // the server key does not match: a security stop, not a network one
  'restricted',
  'password',
  'permission',
  'inactivity',
  'not exist', // the ID is not registered
  'too many',
];

/// Whether this message box is a dropped link the technician app should retry quietly. [firstDrop] is when the first
/// such drop of this session happened (null for the first); the window runs from there, not from each retry.
bool dolphinQuietRetry({
  required bool technician,
  required bool wasConnected,
  required String type,
  required String title,
  required String text,
  required DateTime? firstDrop,
  required DateTime now,
}) {
  if (!technician || !wasConnected) return false;
  if (title != 'Connection Error') return false;
  if (type != 'error' && type != 'relay-hint' && type != 'relay-hint2') return false;
  final t = text.toLowerCase();
  if (_notTransient.any(t.contains)) return false;
  return firstDrop == null || now.difference(firstDrop) < kDolphinReconnectWindow;
}

/// Seconds before retry number [attempt] (0 first): quick at first, then every 5 s, not upstream's doubling (which would
/// wait 64 s once the window is half gone).
Duration dolphinRetryDelay(int attempt) {
  const steps = [1, 2, 3, 5];
  return Duration(seconds: steps[min(max(attempt, 0), steps.length - 1)]);
}
