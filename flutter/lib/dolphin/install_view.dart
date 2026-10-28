import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Our installer replaces upstream's form (UX-2). Upstream installs in a thread and then exits this process, and the
/// installed app opens itself (src/ui_interface.rs install_me; Plan 13 F7), so "done" is the Dolphin Connect window.
const kDolphinInstallView = true;

class DolphinInstallView extends StatefulWidget {
  final VoidCallback onInstall;

  /// Upstream's «Run without install»; hidden when null.
  final VoidCallback? onRunWithoutInstall;

  /// True only when the start-menu and desktop shortcut options were read and are on; else the text promises none.
  final bool shortcutsOn;

  const DolphinInstallView(
      {super.key, required this.onInstall, this.onRunWithoutInstall, this.shortcutsOn = false});

  @override
  State<DolphinInstallView> createState() => _DolphinInstallViewState();
}

class _DolphinInstallViewState extends State<DolphinInstallView> {
  bool _installing = false;
  bool _stuck = false;
  bool _ran = false;
  Timer? _timer;

  /// After this long with the install not done, the customer may press «نصب» again (UAC "No" leaves no signal).
  static const stuckAfter = Duration(seconds: 60);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _install() {
    setState(() {
      _installing = true;
      _stuck = false;
    });
    _timer?.cancel();
    _timer = Timer(stuckAfter, () {
      if (mounted) setState(() => _stuck = true);
    });
    widget.onInstall();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.onRunWithoutInstall;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: DolphinColors.ground,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('نصب دلفین کانکت',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
              const SizedBox(height: 10),
              Text(
                  widget.shortcutsOn
                      ? 'دلفین کانکت روی این رایانه نصب می‌شود و میانبرش روی دسکتاپ و در منوی Start قرار می‌گیرد. پس از نصب، برنامه خودش باز می‌شود.'
                      : 'برنامه در رایانه‌ی شما نصب می‌شود. پس از نصب، برنامه خودش باز می‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DolphinColors.muted, height: 1.8)),
              const SizedBox(height: 22),
              if (_installing) ...[
                const LinearProgressIndicator(color: DolphinColors.azure, backgroundColor: DolphinColors.azureTint),
                const SizedBox(height: 12),
                const Text('در حال نصب… اگر ویندوز اجازه خواست، «Yes» (یا «بله») را بزنید.',
                    textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted)),
                if (_stuck) ...[
                  const SizedBox(height: 8),
                  const Text('اگر پنجره‌ی اجازه‌ی ویندوز را بستید یا «نه» زدید، دوباره «نصب» را بزنید.',
                      textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted)),
                  const SizedBox(height: 12),
                  SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: DolphinColors.azure,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control))),
                    onPressed: _install,
                    child: const Text('نصب', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                ],
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: DolphinColors.azure,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control))),
                    onPressed: _install,
                    child: const Text('نصب', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                if (run != null) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: _ran ? null : () {
                    setState(() => _ran = true);
                    run();
                  }, child: const Text('فقط این بار اجرا شود (بدون نصب)')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
