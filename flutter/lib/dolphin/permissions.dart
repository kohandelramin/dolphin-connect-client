import 'package:flutter/material.dart';

import 'theme.dart';

/// What the customer allows right now, as the technician's client last heard it (FfiModel.permissions, updated live
/// when the customer switches something; Plan 13 F6). A permission never mentioned counts as allowed, as upstream does.
List<(String, bool)> permissionStates(Map<String, bool> p) => [
      ('ماوس و صفحه‌کلید', p['keyboard'] != false),
      ('کپی و چسباندن', p['clipboard'] != false),
      ('انتقال فایل', p['file'] != false),
    ];

/// DD-46: the customer's PC says it paused or resumed with a message box of this type (src/dolphin_session_core.rs
/// PAUSE_MSGTYPE, PAUSED_TITLE, RESUMED_TITLE). Both apps are ours, so no new network message was needed.
const kDolphinPauseMsgType = 'dolphin-pause';
const kDolphinPauseMsgPaused = 'dolphin-paused';
const kDolphinPauseMsgResumed = 'dolphin-resumed';

/// True: the customer paused; false: resumed; null: not a pause message (upstream handles it). Hooked into
/// `FfiModel.handleMsgBox` (flutter/lib/models/model.dart, marked `Dolphin Connect (DD-46)`).
bool? dolphinPauseFromMsgBox(dynamic type, dynamic title) {
  if (type != kDolphinPauseMsgType) return null;
  if (title == kDolphinPauseMsgPaused) return true;
  if (title == kDolphinPauseMsgResumed) return false;
  return null;
}

/// Over the technician's picture during a pause.
const kDolphinCustomerPaused = 'مشتری مکث کرد';
const kDolphinCustomerPausedNote = 'تا مشتری «ادامه» را بزند، تصویر و کنترل متوقف است. اتصال برقرار می‌ماند.';

/// A small strip at the bottom of the technician's remote window (UX-13), so "copy does not work" is not guesswork on
/// the phone, and the pause card over the picture (DD-46). It never takes input.
class DolphinPermissionStrip extends StatelessWidget {
  final Map<String, bool> permissions;
  /// False until the peer info is set: an unknown permission counts as allowed, which would show a false all-green.
  final bool ready;

  /// DD-46: the customer paused; the picture is the last one before the pause.
  final bool paused;
  const DolphinPermissionStrip({super.key, required this.permissions, this.ready = true, this.paused = false});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build), paint: false); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    if (!ready) return const SizedBox.shrink();
    final states = permissionStates(permissions);
    final strip = IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: DolphinColors.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('اجازه‌های مشتری:', style: TextStyle(fontSize: 11.5, color: DolphinColors.muted)),
              for (final s in states) ...[
                const SizedBox(width: 10),
                Icon(s.$2 ? Icons.check_circle : Icons.block,
                    size: 14, color: s.$2 ? DolphinColors.aqua : DolphinColors.danger),
                const SizedBox(width: 4),
                Text(s.$1, style: TextStyle(fontSize: 11.5, color: s.$2 ? DolphinColors.ink : DolphinColors.dangerText)),
              ],
            ]),
          ),
        ),
      ),
    );
    if (!paused) return strip;
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: ColoredBox(color: DolphinColors.ink.withOpacity(0.8)))),
      IgnorePointer(
        child: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(DolphinRadii.card)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.pause_circle_filled, size: 40, color: DolphinColors.azureText),
                SizedBox(height: 8),
                Text(kDolphinCustomerPaused,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                SizedBox(height: 4),
                Text(kDolphinCustomerPausedNote,
                    textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, height: 1.6)),
              ]),
            ),
          ),
        ),
      ),
      strip,
    ]);
  }
}
