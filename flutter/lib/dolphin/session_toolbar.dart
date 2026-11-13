import 'package:flutter/material.dart';

import 'digits.dart';
import 'tech_theme.dart';

/// DD-28: the Persian quick bar at the start of the technician's session toolbar. Upstream's menus stay after it; this
/// bar only brings the common actions to one click, in Persian, with tooltips. Everything here is display or an action
/// upstream already has (session_toolbar_hook.dart wires them); nothing changes the connection, codec or network.

/// The delay upstream's quality monitor reports (`QualityMonitorData.delay`, from the peer's TestDelay; it arrives
/// whether or not the monitor is shown). Null when there is none yet or it is not a number.
int? parseDelay(String? s) {
  final v = int.tryParse((s ?? '').trim());
  return v == null || v < 0 ? null : v;
}

/// «۴۵ میلی‌ثانیه», or «—» before the first measurement.
String latencyLabel(int? ms) => ms == null ? '—' : '${faDigits('$ms')} میلی‌ثانیه';

enum DolphinLatency { good, fair, slow }

/// Only a colour for the number; the thresholds are a reading aid, not a setting.
DolphinLatency latencyLevel(int ms) => ms <= 150
    ? DolphinLatency.good
    : ms <= 400
        ? DolphinLatency.fair
        : DolphinLatency.slow;

/// «مستقیم» for a peer-to-peer link, «از سرور دلفین» through our relay (hbbr); null while upstream does not know yet.
String? routeLabel(bool? direct) => direct == null ? null : (direct ? 'مستقیم' : 'از سرور دلفین');

const kLatencyNote = 'فقط نمایش است و چیزی را در اتصال عوض نمی‌کند.';

String latencyTooltip(int? ms, bool? direct) {
  final route = direct == null
      ? ''
      : direct
          ? 'اتصال مستقیم بین دو رایانه.\n'
          : 'اتصال از راه سرور دلفین (relay).\n';
  return 'تأخیر تا رایانه‌ی مشتری: ${latencyLabel(ms)}\n$route$kLatencyNote';
}

/// What the bar shows; built from the session by the hook, plain values here so the widget is testable.
class DolphinBarState {
  final int? latencyMs;
  final bool? direct;
  final bool viewOnly;
  final bool myCursor;
  final bool follow;

  /// The follow toggle only works with several screens (upstream's rule); the button stays, disabled, otherwise.
  final bool canFollow;

  /// DD-52: the customer's screen count; «صفحه‌ها» shows from 2.
  final int screens;

  const DolphinBarState({
    this.latencyMs,
    this.direct,
    this.viewOnly = false,
    this.myCursor = false,
    this.follow = false,
    this.canFollow = false,
    this.screens = 1,
  });
}

/// The tooltips, one place, so tests and the hook agree.
class DolphinBarText {
  static const ctrlAltDel = 'فرستادن Ctrl+Alt+Del';
  static const lock = 'قفل کردن رایانه‌ی مشتری';
  static const files = 'انتقال فایل';
  static const screenshot = 'عکس صفحه';
  static const keyboardLayout = 'زبان صفحه‌کلید مشتری';
  static const viewOnly = 'فقط تماشا';
  static const myCursor = 'نشانگر خودم';
  static const follow = 'دنبال کردن پنجره‌ی مشتری';
  static const followNeedsScreens = 'دنبال کردن پنجره‌ی مشتری (وقتی مشتری چند صفحه دارد)';
  static const screens = 'صفحه‌های مشتری';
  static const noPicture = 'تصویر نمی‌آید یا صفحه قفل است؟';
  static const collapse = 'جمع کردن نوار';
  static const notReady = '(به‌زودی)';
}

/// One square button of the bar: 32 px, as upstream's toolbar buttons. [on] is null for an action, true or false for a
/// toggle. Disabled (dimmed, tooltip kept) when [onPressed] is null.
class DolphinBarButton extends StatelessWidget {
  final IconData? icon;
  final String? label; // instead of an icon (Ctrl+Alt+Del)
  final String tooltip;
  final VoidCallback? onPressed;
  final bool? on;
  const DolphinBarButton(
      {super.key, this.icon, this.label, required this.tooltip, required this.onPressed, this.on});

  /// A toggle that is on, or an action: azure with white (5.45:1). A toggle that is off: the surface with a border.
  bool get filled => on != false;

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final fg = filled ? Colors.white : p.ink;
    final bg = filled ? const Color(0xFF1462E0) : p.surface;
    final shown = on == true ? '$tooltip: روشن' : (on == false ? '$tooltip: خاموش' : tooltip);
    return Tooltip(
      message: shown,
      child: Semantics(
        button: true,
        toggled: on,
        enabled: onPressed != null,
        label: tooltip,
        child: Opacity(
          opacity: onPressed == null ? 0.45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: filled ? BorderSide.none : BorderSide(color: p.lineStrong)),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onPressed,
                child: SizedBox(
                  height: 32,
                  width: label == null ? 32 : null,
                  child: Center(
                    child: label != null
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(label!,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)))
                        : Icon(icon, size: 18, color: fg),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «۴۵ میلی‌ثانیه · مستقیم» with a coloured dot; display only.
class DolphinLatencyChip extends StatelessWidget {
  final int? ms;
  final bool? direct;
  const DolphinLatencyChip({super.key, required this.ms, required this.direct});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final level = ms == null ? null : latencyLevel(ms!);
    final color = switch (level) {
      null => p.muted,
      DolphinLatency.good => p.okText,
      DolphinLatency.fair => p.warnText,
      DolphinLatency.slow => p.dangerText,
    };
    final route = routeLabel(direct);
    return Tooltip(
      message: latencyTooltip(ms, direct),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 32,
        decoration: BoxDecoration(
            color: p.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(latencyLabel(ms), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          if (route != null) ...[
            Text(' · ', style: TextStyle(color: p.muted, fontSize: 12)),
            Text(route, style: TextStyle(color: p.ink, fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

/// The bar. Each callback null → that button is disabled (or, for «صفحه‌ها», hidden). [axis] follows the toolbar's
/// docking edge (vertical when docked left or right).
class DolphinSessionBar extends StatelessWidget {
  final DolphinBarState state;
  final Axis axis;
  final VoidCallback? onCtrlAltDel;
  final VoidCallback? onLock;
  final VoidCallback? onFiles;
  final VoidCallback? onViewOnly;
  final VoidCallback? onMyCursor;
  final VoidCallback? onFollow;
  final VoidCallback? onNoPicture;
  final VoidCallback? onCollapse;

  /// DD-52: the monitor picker, shown in a menu under «صفحه‌ها»; it gets a callback that closes the menu.
  final Widget Function(BuildContext context, VoidCallback close)? screensMenu;

  // ---- Plan 18 Phase 3, p3-panel's buttons (DD-51 «عکس صفحه», DD-6 «زبان صفحه‌کلید»). The hook passes
  // DolphinToolbarHooks.onScreenshot / onKeyboardLayout (session_toolbar_hook.dart); null until p3-panel wires them,
  // and then the button is disabled with «(به‌زودی)» in its tooltip.
  final VoidCallback? onScreenshot;
  final VoidCallback? onKeyboardLayout;
  // ---- end of p3-panel's buttons

  const DolphinSessionBar({
    super.key,
    required this.state,
    this.axis = Axis.horizontal,
    this.onCtrlAltDel,
    this.onLock,
    this.onFiles,
    this.onViewOnly,
    this.onMyCursor,
    this.onFollow,
    this.onNoPicture,
    this.onCollapse,
    this.screensMenu,
    this.onScreenshot,
    this.onKeyboardLayout,
  });

  static String _soon(String t, Object? wired) => wired == null ? '$t ${DolphinBarText.notReady}' : t;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      DolphinLatencyChip(ms: state.latencyMs, direct: state.direct),
      DolphinBarButton(label: 'Ctrl+Alt+Del', tooltip: DolphinBarText.ctrlAltDel, onPressed: onCtrlAltDel),
      DolphinBarButton(icon: Icons.lock_outline, tooltip: DolphinBarText.lock, onPressed: onLock),
      DolphinBarButton(icon: Icons.folder_outlined, tooltip: DolphinBarText.files, onPressed: onFiles),
      // ---- p3-panel (DD-51, DD-6)
      DolphinBarButton(
          icon: Icons.photo_camera_outlined,
          tooltip: _soon(DolphinBarText.screenshot, onScreenshot),
          onPressed: onScreenshot),
      DolphinBarButton(
          icon: Icons.translate,
          tooltip: _soon(DolphinBarText.keyboardLayout, onKeyboardLayout),
          onPressed: onKeyboardLayout),
      // ---- end p3-panel
      if (state.screens > 1 && screensMenu != null) _ScreensButton(menu: screensMenu!),
      DolphinBarButton(
          icon: Icons.visibility_outlined, tooltip: DolphinBarText.viewOnly, on: state.viewOnly, onPressed: onViewOnly),
      DolphinBarButton(
          icon: Icons.mouse_outlined, tooltip: DolphinBarText.myCursor, on: state.myCursor, onPressed: onMyCursor),
      DolphinBarButton(
          icon: Icons.center_focus_strong_outlined,
          tooltip: state.canFollow ? DolphinBarText.follow : DolphinBarText.followNeedsScreens,
          on: state.follow,
          onPressed: state.canFollow ? onFollow : null),
      DolphinBarButton(icon: Icons.help_outline, tooltip: DolphinBarText.noPicture, onPressed: onNoPicture),
      if (onCollapse != null)
        DolphinBarButton(
            icon: axis == Axis.horizontal ? Icons.expand_less : Icons.chevron_left,
            tooltip: DolphinBarText.collapse,
            onPressed: onCollapse),
    ];
    return DolphinTechTheme(
      paint: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// «صفحه‌ها»: opens the monitor picker (DD-52) in a menu.
class _ScreensButton extends StatefulWidget {
  final Widget Function(BuildContext context, VoidCallback close) menu;
  const _ScreensButton({required this.menu});

  @override
  State<_ScreensButton> createState() => _ScreensButtonState();
}

class _ScreensButtonState extends State<_ScreensButton> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
        controller: _controller,
        menuChildren: [
          DolphinTechTheme(paint: false, child: Builder(builder: (c) => widget.menu(c, _controller.close))),
        ],
        child: DolphinBarButton(
            icon: Icons.desktop_windows_outlined,
            tooltip: DolphinBarText.screens,
            onPressed: () => _controller.isOpen ? _controller.close() : _controller.open()),
      );
}
