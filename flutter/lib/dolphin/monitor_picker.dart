import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'digits.dart';
import 'tech_theme.dart';

/// DD-52: the customer's screens as small pictures of their layout, to choose which one to see. The pictures are the
/// screens' shapes and places (upstream's peer info: position, size, scale), not live images: a live image of every
/// screen would mean capturing and sending each one, which changes the video traffic (the owner's speed rule).

/// One of the customer's screens, in the peer's desktop coordinates (logical pixels, as upstream draws them).
class DolphinScreen {
  final double x, y, width, height;

  /// The screen's real pixels, for the label (upstream's `Display.width` before the scale).
  final int pixelWidth, pixelHeight;
  const DolphinScreen(
      {required this.x,
      required this.y,
      required this.width,
      required this.height,
      required this.pixelWidth,
      required this.pixelHeight});
}

/// Where each screen goes in a [box], keeping the customer's arrangement and proportions, centred. The geometry is
/// physical: it is never mirrored for right-to-left.
List<Rect> screenLayout(List<DolphinScreen> screens, Size box, {double gap = 4}) {
  if (screens.isEmpty) return const [];
  var left = double.infinity, top = double.infinity, right = -double.infinity, bottom = -double.infinity;
  for (final s in screens) {
    left = math.min(left, s.x);
    top = math.min(top, s.y);
    right = math.max(right, s.x + s.width);
    bottom = math.max(bottom, s.y + s.height);
  }
  final w = right - left, h = bottom - top;
  if (w <= 0 || h <= 0) return [for (final _ in screens) Rect.zero];
  final scale = math.min(box.width / w, box.height / h);
  final dx = (box.width - w * scale) / 2, dy = (box.height - h * scale) / 2;
  return [
    for (final s in screens)
      Rect.fromLTWH(dx + (s.x - left) * scale + gap / 2, dy + (s.y - top) * scale + gap / 2,
          math.max(0, s.width * scale - gap), math.max(0, s.height * scale - gap)),
  ];
}

/// «صفحه‌ی ۲»
String screenName(int index) => 'صفحه‌ی ${faDigits('${index + 1}')}';

/// «۱۹۲۰ × ۱۰۸۰»
String screenSize(DolphinScreen s) => '${faDigits('${s.pixelWidth}')} × ${faDigits('${s.pixelHeight}')}';

/// The picker: a title, the layout, a line of help. The screen being viewed is filled azure; [primary] (the one the
/// session started on, upstream's `primaryDisplay`) says «اصلی». Tapping another screen calls [onPick].
class DolphinMonitorPicker extends StatelessWidget {
  final List<DolphinScreen> screens;
  final int current;
  final int? primary;
  final ValueChanged<int> onPick;
  final Size box;
  const DolphinMonitorPicker(
      {super.key,
      required this.screens,
      required this.current,
      required this.onPick,
      this.primary,
      this.box = const Size(320, 150)});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final rects = screenLayout(screens, box);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('صفحه‌های مشتری', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SizedBox(
            width: box.width,
            height: box.height,
            // The customer's arrangement is physical (left is left), so the stack is laid out left to right.
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(children: [
                for (var i = 0; i < screens.length; i++)
                  Positioned.fromRect(
                      rect: rects[i],
                      child: _ScreenTile(
                          index: i,
                          screen: screens[i],
                          selected: i == current,
                          primary: i == primary,
                          onTap: i == current ? null : () => onPick(i))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text('روی صفحه‌ای که می‌خواهید ببینید بزنید.', style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class _ScreenTile extends StatelessWidget {
  final int index;
  final DolphinScreen screen;
  final bool selected;
  final bool primary;
  final VoidCallback? onTap;
  const _ScreenTile(
      {required this.index, required this.screen, required this.selected, required this.primary, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final fg = selected ? Colors.white : p.ink;
    final sub = selected ? Colors.white : p.muted;
    return Tooltip(
      message: selected ? '${screenName(index)} (همین را می‌بینید)' : screenName(index),
      child: Material(
        color: selected ? p.fill : p.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(p.radiusTiny),
            side: BorderSide(color: selected ? p.fill : p.lineStrong, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(p.radiusTiny),
          onTap: onTap,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(faDigits('${index + 1}'),
                      style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(screenSize(screen), textDirection: TextDirection.ltr, style: TextStyle(color: sub, fontSize: 11)),
                  if (primary) Text('اصلی', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
