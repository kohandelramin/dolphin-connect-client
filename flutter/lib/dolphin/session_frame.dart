import 'dart:ui' show Color;

/// Plan 19 (C3, idea from AnyDesk): «کادر رنگی دور صفحه», a coloured frame around the customer's screen while a
/// technician is connected, so a glance at the screen says somebody is in. The customer's choice, off by default; set in
/// the session window or in «تنظیمات» (C5), kept as a local option of this Windows account.
///
/// The frame itself is drawn by the session window's process in Rust (src/dolphin_frame.rs): four thin always-on-top,
/// click-through, borderless windows along the edges of every screen, asked for with `main_set_common("dolphin-frame",
/// "#rrggbb")` and removed with "". They belong to the session window's process, so they can never outlive it.
const kDolphinFrameLocal = 'dolphin-session-frame';

/// `main_set_common` key.
const kDolphinFrameCommon = 'dolphin-frame';

const kFrameLabel = 'کادر رنگی دور صفحه';
const kFrameSettingLabel = 'کادر رنگی در جلسه';

/// Off unless the customer turned it on ("Y").
bool frameOn(String raw) => raw.trim() == 'Y';

String frameValue(bool on) => on ? 'Y' : '';

/// The frame shows only while a technician is really connected (accepted, not ended) and the customer wants it.
bool frameWanted({required bool enabled, required bool liveSession}) => enabled && liveSession;

/// What the Rust side gets: "#rrggbb" while the frame should show, "" to remove it.
String frameCommand({required bool show, required Color color}) {
  if (!show) return '';
  String two(int c) => c.toRadixString(16).padLeft(2, '0');
  return '#${two(color.red)}${two(color.green)}${two(color.blue)}';
}
