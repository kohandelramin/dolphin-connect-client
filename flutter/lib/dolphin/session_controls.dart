import 'package:flutter/widgets.dart';

import 'digits.dart';

/// The customer's controls while a technician is connected (Plan 18 Phase 2: DD-36 small window, DD-37 input off,
/// DD-45 live permissions, DD-46 pause). Pure, so it is unit-tested; the window is connection.dart, the view
/// connection_view.dart, the rules on the PC src/dolphin_session_core.rs.

/// `bind.cmSwitchPermission` name for «مکث» (enabled) and «ادامه» (disabled); src/dolphin_session_core.rs PAUSE_SWITCH.
const kDolphinPauseSwitch = 'dolphin_pause';

/// DD-36: the session window. The connection window is 320 × 520 in the top-right corner for the prompt
/// (kConnectionManagerWindowSizeClosedChat, Plan 19 C2); during a session ours is 300 × 380 in the bottom-right corner,
/// above the taskbar (Plan 19 C3), so it covers less of the customer's screen. «پایان» stays pinned at its bottom.
const kDolphinSessionWindowSize = Size(300, 380);

enum DolphinWindowMode { full, compact }

/// The accept prompt and the ended screen need the full window; a live session is the small one.
DolphinWindowMode windowModeFor({required bool authorized, required bool disconnected}) =>
    authorized && !disconnected ? DolphinWindowMode.compact : DolphinWindowMode.full;

/// Whether the window must change: only for the tab on screen, and only when the size differs from what we set last.
bool windowNeedsResize({required bool selected, required DolphinWindowMode wanted, DolphinWindowMode? current}) =>
    selected && wanted != current;

/// Upstream resized the window behind our back (start-up show, the chat closing): the size is not the one the window
/// reported after we set the small one. An open chat is wider than tall (700 × 490) and is left alone. Compared with
/// what the window itself reported, so display scaling does not matter.
bool windowNeedsRefit({required Size? seen, required Size current}) =>
    seen != null && current != seen && current.width < current.height;

/// DD-37: shown at once when the technician blocks the customer's mouse and keyboard.
const kDolphinInputOffTitle = 'ماوس و صفحه‌کلید شما خاموش است';

/// While input is blocked the customer cannot click anything here, so the way back is the phone.
const kDolphinInputOffHint = 'برای روشن شدن دوباره، به کارشناس بگویید.';

/// When the block started, kept from the first time it was seen until it ends.
DateTime? inputOffSince(DateTime? since, bool blocked, DateTime now) => blocked ? (since ?? now) : null;

/// «همین حالا» under a minute, then «۳ دقیقه پیش», «۱ ساعت و ۵ دقیقه پیش».
String agoText(DateTime since, DateTime now) {
  final d = now.isBefore(since) ? Duration.zero : now.difference(since);
  if (d.inMinutes < 1) return 'همین حالا';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${faDigits('$m')} دقیقه پیش';
  if (m == 0) return '${faDigits('$h')} ساعت پیش';
  return '${faDigits('$h')} ساعت و ${faDigits('$m')} دقیقه پیش';
}

/// Who blocked it and since when: «علی رضایی خاموش کرد، ۳ دقیقه پیش».
String inputOffDetail(String who, DateTime since, DateTime now) => '$who خاموش کرد، ${agoText(since, now)}';

/// DD-46: the buttons and the line under them.
const kDolphinPauseLabel = 'مکث';
const kDolphinResumeLabel = 'ادامه';
const kDolphinPausedTitle = 'مکث است';
const kDolphinPausedNote = 'کارشناس تصویر را نمی‌بیند و کنترلی ندارد. برای ادامه، «ادامه» را بزنید.';
const kDolphinPauseHint = 'مثلاً هنگام نوشتن رمز بانک، «مکث» را بزنید.';

/// DD-45: the three permissions, by `bind.cmSwitchPermission` name, with the label the customer reads (Plan 19 C2/C3
/// labels, access_profile.dart kGrantLabels; sound is the fourth, shown when the organization offers it).
const kDolphinPermissionLabels = [
  ('keyboard', 'ماوس و صفحه‌کلید'),
  ('clipboard', 'کلیپ‌بورد'),
  ('file', 'انتقال فایل'),
];
