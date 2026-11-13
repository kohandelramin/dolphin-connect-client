import 'dart:convert';
import 'dart:math' as math;

import 'panel_bridge.dart';

/// Plan 18 Phase 3 in the technician's remote window: the side pane with the portal's panel for this PC (DD-49), its
/// «چسباندن» (DD-50), «عکس صفحه» to the open call (DD-51) and the customer's keyboard language (DD-6). Pure, so it is
/// unit-tested; the widgets are side_pane.dart, the customer's side src/dolphin_panel_core.rs.

/// Width of the pane beside the picture. The portal page is built for this (app/src/app/staff/side, narrow).
const kDolphinSideWidth = 340.0;

/// Local option: "Y" while the pane is open. Hidden by default; remembered for the next remote window.
const kDolphinSideOption = 'dolphin-side-pane';

bool sideOpenFrom(String stored) => stored == 'Y';

/// The portal page for this PC, or null when the peer's ID is not one the portal knows the shape of (then no pane).
String? sidePanePath(String peerId) {
  final id = peerId.replaceAll(RegExp(r'\s'), '');
  return panelIdPattern.hasMatch(id) ? '/staff/side/$id' : null;
}

/// `session_set_common` keys the Rust side turns into a request to this session's PC (src/dolphin_panel_core.rs).
const kDolphinPasteKey = 'dolphin-paste';
const kDolphinKeyboardKey = 'dolphin-kbd';

/// The languages offered (DD-6). The PC switches only to a layout it already has.
const kDolphinKeyboardChoices = [('fa', 'فارسی'), ('en', 'انگلیسی')];

/// What the session looks like when the technician asks for something.
class SessionState {
  final bool live;
  final bool keyboard;
  final bool clipboard;
  final bool viewOnly;
  final bool paused;
  const SessionState(
      {required this.live, this.keyboard = true, this.clipboard = true, this.viewOnly = false, this.paused = false});
}

const kNotLive = 'جلسه هنوز وصل نیست.';
const kViewOnly = 'حالت «فقط تماشا» روشن است.';
const kPausedNow = 'مشتری مکث کرده است.';
const kKeyboardOff = 'مشتری ماوس و صفحه‌کلید را خاموش کرده است.';
const kClipboardOff = 'مشتری «کپی و چسباندن» را خاموش کرده است.';
const kWrongPc = 'این متن برای رایانه‌ی دیگری بود؛ چسبانده نشد.';

/// Why a keyboard-language change cannot be asked for now; null when it can.
String? keyboardProblem(SessionState s) {
  if (!s.live) return kNotLive;
  if (s.paused) return kPausedNow;
  if (s.viewOnly) return kViewOnly;
  if (!s.keyboard) return kKeyboardOff;
  return null;
}

/// DD-50: a paste goes only to the PC of this remote window ([peerId]), only while the session is live and the
/// customer allows keyboard and clipboard. Null when it may go.
String? pasteProblem(PanelMessage m, String peerId, SessionState s) {
  if (m.type != 'dolphin-paste') return kWrongPc;
  if (m.id != peerId.replaceAll(RegExp(r'\s'), '')) return kWrongPc;
  final k = keyboardProblem(s);
  if (k != null) return k;
  if (!s.clipboard) return kClipboardOff;
  return null;
}

/// How long the window waits for the PC's answer before saying the customer's app may be old.
const kDolphinReplyWait = Duration(seconds: 8);
const kNoReply = 'برنامه‌ی مشتری جواب نداد؛ شاید نسخه‌ی آن قدیمی است.';

/// The PC's answer: `MessageBox` type "dolphin-panel", title the outcome code, text the Persian line.
const kDolphinPanelMsgType = 'dolphin-panel';
const _okCodes = {'pasted', 'switched-fa', 'switched-en'};

/// (ok, text) for a "dolphin-panel" message box; null for anything else (upstream handles it). A text that is not a
/// short line is replaced by a plain one.
(bool, String)? panelResultFromMsgBox(dynamic type, dynamic title, dynamic text) {
  if (type != kDolphinPanelMsgType || title is! String) return null;
  final ok = _okCodes.contains(title);
  final line = text is String ? text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim() : '';
  if (line.isEmpty || line.length > 160) return (ok, ok ? 'انجام شد.' : 'انجام نشد.');
  return (ok, line);
}

// DD-51: the screenshot.

/// The portal takes at most this much base64 (app/src/lib/app-bridge.ts SCREENSHOT_MAX_BASE64).
const kScreenshotMaxBase64 = 6 * 1024 * 1024;

int base64Length(int bytes) => 4 * ((bytes + 2) ~/ 3);

bool screenshotFits(int bytes) => base64Length(bytes) <= kScreenshotMaxBase64;

/// The PNG signature: the portal accepts nothing else.
bool isPng(List<int> b) =>
    b.length > 8 &&
    b[0] == 0x89 &&
    b[1] == 0x50 &&
    b[2] == 0x4e &&
    b[3] == 0x47 &&
    b[4] == 0x0d &&
    b[5] == 0x0a &&
    b[6] == 0x1a &&
    b[7] == 0x0a;

/// The width to scale a PNG of [bytes] and [width] to so it fits, with a margin (PNG size follows the area); null
/// when it already fits or is too small to scale further.
int? screenshotTargetWidth(int bytes, int width) {
  if (screenshotFits(bytes)) return null;
  const minWidth = 480;
  if (width <= minWidth) return null;
  final maxBytes = kScreenshotMaxBase64 * 3 ~/ 4;
  final scale = math.sqrt(maxBytes / bytes) * 0.9;
  return math.max(minWidth, (width * scale).floor());
}

/// Why no screenshot can be taken now; null when it can.
String? screenshotProblem({required bool live, required bool supported, required bool allDisplays}) {
  if (!live) return kNotLive;
  if (!supported) return 'برنامه‌ی مشتری عکس صفحه را پشتیبانی نمی‌کند.';
  if (allDisplays) return 'در نمای «همه‌ی صفحه‌ها» عکس گرفته نمی‌شود؛ یک صفحه را انتخاب کنید.';
  return null;
}

const kShotTaking = 'در حال گرفتن عکس صفحه…';
const kShotSent = 'عکس صفحه به پنل کناری رفت.';
const kShotFailed = 'عکس صفحه گرفته نشد؛ دوباره امتحان کنید.';
const kShotTooBig = 'عکس صفحه بزرگ‌تر از حد پورتال بود و کوچک هم نشد.';
const kShotNoPane = 'پنل کناری باز نشد؛ عکس فرستاده نشد. اگر وارد پنل نشده‌اید، اول وارد شوید.';
const kShotWait = Duration(seconds: 30);

/// The message to the side pane (app/src/lib/app-bridge.ts parseAppMessage).
String screenshotMessage(String pngBase64, String peerId) =>
    jsonEncode({'type': 'dolphin-screenshot', 'png': pngBase64, 'id': peerId.replaceAll(RegExp(r'\s'), '')});

/// Upstream's screenshot answer keeps the picture in the client until told what to do with it; we save it to a
/// temporary file we delete at once (`sessionHandleScreenshot`, src/client/screenshot.rs: "0:<path>").
String screenshotSaveAction(String path) => '0:$path';
