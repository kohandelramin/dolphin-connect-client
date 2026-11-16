import 'package:flutter/material.dart';

import 'digits.dart';
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

/// The local option that keeps the strip folded between sessions ('Y' folded), as the top toolbar keeps its own state.
const kDolphinPermStripFoldedOption = 'dolphin-perm-strip-folded';

/// Where along the bottom edge the strip sits (-1 left … 0 middle … 1 right), kept between sessions as a number.
const kDolphinPermStripXOption = 'dolphin-perm-strip-x';

/// The saved position, or the middle when there is none or it is not a number in range.
double permStripXFrom(String saved) {
  final v = double.tryParse(saved.trim());
  return v == null || v.isNaN ? 0 : v.clamp(-1.0, 1.0).toDouble();
}

/// Folded, the strip is a small tab; a red mark with the count when something is off, so a fold never hides a block.
String permissionsFoldedTooltip(Map<String, bool> p) {
  final off = permissionStates(p).where((s) => !s.$2).map((s) => s.$1).toList();
  return off.isEmpty ? 'نمایش اجازه‌های مشتری (همه روشن)' : 'نمایش اجازه‌های مشتری (خاموش: ${off.join('، ')})';
}

/// A small strip at the bottom of the technician's remote window (UX-13), so "copy does not work" is not guesswork on
/// the phone, and the pause card over the picture (DD-46). The ▾ folds it into a small tab at the bottom edge (like the
/// top toolbar's), the tab's ▴ opens it again; open or folded it is dragged left or right along the edge (owner
/// 2026-11-16). Only the strip itself takes input; the picture around it still does.
class DolphinPermissionStrip extends StatefulWidget {
  final Map<String, bool> permissions;
  /// False until the peer info is set: an unknown permission counts as allowed, which would show a false all-green.
  final bool ready;

  /// DD-46: the customer paused; the picture is the last one before the pause.
  final bool paused;

  /// Folded at the start (the remote page reads [kDolphinPermStripFoldedOption]).
  final bool initiallyFolded;

  /// The technician folded or opened it (the remote page saves it).
  final ValueChanged<bool>? onFoldedChanged;

  /// Where it starts along the bottom edge (-1 left, 0 middle, 1 right; [kDolphinPermStripXOption]).
  final double initialX;

  /// Dropped somewhere else after a drag (the remote page saves it).
  final ValueChanged<double>? onMoved;
  const DolphinPermissionStrip(
      {super.key,
      required this.permissions,
      this.ready = true,
      this.paused = false,
      this.initiallyFolded = false,
      this.onFoldedChanged,
      this.initialX = 0,
      this.onMoved});

  @override
  State<DolphinPermissionStrip> createState() => _DolphinPermissionStripState();
}

class _DolphinPermissionStripState extends State<DolphinPermissionStrip> {
  late bool _folded = widget.initiallyFolded;
  late double _x = widget.initialX.clamp(-1.0, 1.0).toDouble();
  final _childKey = GlobalKey();

  /// A drag of [dx] pixels in a window [width] wide: the strip follows the pointer, never past an edge.
  void _drag(double dx, double width) {
    final child = _childKey.currentContext?.size?.width ?? 0;
    final room = width - child;
    if (room <= 0) return;
    setState(() => _x = (_x + dx * 2 / room).clamp(-1.0, 1.0).toDouble());
  }

  void _toggle() {
    setState(() => _folded = !_folded);
    widget.onFoldedChanged?.call(_folded);
  }

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build), paint: false); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _foldButton(IconData icon, String tooltip, Key key) => Tooltip(
        message: tooltip,
        child: InkWell(
          key: key,
          onTap: _toggle,
          borderRadius: BorderRadius.circular(99),
          child: Padding(padding: const EdgeInsets.all(2), child: Icon(icon, size: 18, color: DolphinColors.muted)),
        ),
      );

  Widget _open(List<(String, bool)> states) => Container(
        key: const ValueKey('perm-strip'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsetsDirectional.only(start: 6, end: 6, top: 3, bottom: 3),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: DolphinColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // The grip says it moves left and right.
          Icon(Icons.drag_indicator, size: 15, color: DolphinColors.muted),
          const SizedBox(width: 4),
          IgnorePointer(
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
          const SizedBox(width: 6),
          _foldButton(Icons.expand_more, 'پنهان کردن اجازه‌های مشتری', const ValueKey('perm-strip-fold')),
        ]),
      );

  /// The folded tab: on the bottom edge, as the top toolbar's tab hangs from the top edge.
  Widget _tab(List<(String, bool)> states) {
    final off = states.where((s) => !s.$2).length;
    return Tooltip(
      message: permissionsFoldedTooltip(widget.permissions),
      child: InkWell(
        key: const ValueKey('perm-strip-unfold'),
        onTap: _toggle,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: DolphinColors.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.expand_less, size: 18, color: DolphinColors.muted),
            const SizedBox(width: 2),
            if (off == 0)
              Icon(Icons.check_circle, size: 13, color: DolphinColors.aqua)
            else ...[
              Icon(Icons.block, size: 13, color: DolphinColors.danger),
              const SizedBox(width: 3),
              Text(faDigits('$off'), style: TextStyle(fontSize: 11.5, color: DolphinColors.dangerText)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _build(BuildContext context) {
    if (!widget.ready) return const SizedBox.shrink();
    final states = permissionStates(widget.permissions);
    // Align passes taps outside its child through to the picture; the strip (or the tab) takes input only on itself.
    final strip = LayoutBuilder(
      builder: (context, box) => Align(
        alignment: Alignment(_x, 1),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(
            key: _childKey,
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => _drag(d.delta.dx, box.maxWidth),
            onHorizontalDragEnd: (_) => widget.onMoved?.call(_x),
            child: Directionality(textDirection: TextDirection.rtl, child: _folded ? _tab(states) : _open(states)),
          ),
        ),
      ),
    );
    if (!widget.paused) return strip;
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
