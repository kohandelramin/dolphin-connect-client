import 'dart:async';

import 'package:flutter/material.dart';

import 'tech_theme.dart';

/// DD-16: when the technician sees no picture (the customer's PC is locked, on the Windows sign-in screen, or its screen
/// is off), a Persian prompt says what is likely going on and offers Ctrl+Alt+Del, waiting, and «قطع».
///
/// Upstream already shows «وصل شد؛ در انتظار تصویر…» (`showConnectedWaitingForImage` in models/model.dart) until the
/// first frame; after [kDolphinNoPictureAfter] of that, the help replaces the plain wait. A picture that shows the
/// sign-in screen, or one that froze when Windows locked (a PC without the installed app cannot capture the lock
/// screen), cannot be told apart from a normal still screen without a new message from the customer's app, so for
/// those the same help opens from the toolbar's «؟» button. Nothing here changes the connection.

/// How long upstream's plain wait shows before the help.
const kDolphinNoPictureAfter = Duration(seconds: 8);

const kNoPictureTitle = 'تصویر صفحه نمی‌آید';
const kNoPictureWhy = 'شاید رایانه‌ی مشتری قفل است، صفحه‌ی ورود ویندوز باز است یا صفحه خاموش است.';
const kNoPictureCad = 'Ctrl+Alt+Del را بفرستید تا صفحه‌ی ورود بیاید؛ مشتری رمز ویندوز خود را وارد کند.';
const kNoPictureAsk = 'از مشتری بخواهید وارد ویندوز شود یا ماوس را تکان دهد.';
const kNoPictureNotInstalled = 'دلفین کانکت روی رایانه‌ی مشتری نصب نیست؛ تا قفل ویندوز باز نشود تصویری نمی‌آید.';

const kNoPictureSendCad = 'فرستادن Ctrl+Alt+Del';
const kNoPictureWait = 'صبر می‌کنم';
const kNoPictureDisconnect = 'قطع';

/// The help's lines. [canCtrlAltDel]: the technician may send it (keyboard allowed, not view-only, and the customer's
/// PC can take it: upstream's `sasEnabled`, which needs the installed service). [installed]: upstream's
/// `platform_additions.is_installed`, null when the customer's app did not say.
List<String> noPictureLines({required bool canCtrlAltDel, bool? installed}) => [
      kNoPictureWhy,
      canCtrlAltDel ? kNoPictureCad : kNoPictureAsk,
      if (installed == false) kNoPictureNotInstalled,
    ];

/// The help itself: title, lines, buttons. Used inside upstream's waiting dialog and in the toolbar's dialog.
class DolphinNoPictureHelp extends StatelessWidget {
  final bool canCtrlAltDel;
  final bool? installed;
  final VoidCallback? onCtrlAltDel;
  final VoidCallback onWait;
  final VoidCallback onDisconnect;
  const DolphinNoPictureHelp(
      {super.key,
      required this.canCtrlAltDel,
      this.installed,
      this.onCtrlAltDel,
      required this.onWait,
      required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final cad = canCtrlAltDel && onCtrlAltDel != null;
    return DolphinTechTheme(
      paint: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_clock_outlined, color: p.accent),
            const SizedBox(width: 8),
            Flexible(
                child: Text(kNoPictureTitle,
                    style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          for (final l in noPictureLines(canCtrlAltDel: cad, installed: installed))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(l, style: TextStyle(color: p.ink, height: 1.6)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (cad) FilledButton(onPressed: onCtrlAltDel, child: const Text(kNoPictureSendCad)),
            OutlinedButton(onPressed: onWait, child: const Text(kNoPictureWait)),
            TextButton(
                style: TextButton.styleFrom(foregroundColor: p.dangerText),
                onPressed: onDisconnect,
                child: const Text(kNoPictureDisconnect)),
          ]),
        ]),
      ),
    );
  }
}

/// Upstream's waiting content ([waiting]) with «قطع», then, after [after] without a picture, the help. «صبر می‌کنم» goes
/// back to the plain wait for another [after]. The dialog closes by itself at the first frame (upstream).
class DolphinWaitingForPicture extends StatefulWidget {
  final Widget waiting;
  final Duration after;
  final bool canCtrlAltDel;
  final bool? installed;
  final VoidCallback? onCtrlAltDel;
  final VoidCallback onDisconnect;
  const DolphinWaitingForPicture(
      {super.key,
      required this.waiting,
      this.after = kDolphinNoPictureAfter,
      required this.canCtrlAltDel,
      this.installed,
      this.onCtrlAltDel,
      required this.onDisconnect});

  @override
  State<DolphinWaitingForPicture> createState() => _DolphinWaitingForPictureState();
}

class _DolphinWaitingForPictureState extends State<DolphinWaitingForPicture> {
  Timer? _timer;
  bool _help = false;

  void _wait() {
    _timer?.cancel();
    if (_help) setState(() => _help = false);
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _help = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _wait();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_help) {
      return DolphinNoPictureHelp(
          canCtrlAltDel: widget.canCtrlAltDel,
          installed: widget.installed,
          onCtrlAltDel: widget.onCtrlAltDel,
          onWait: _wait,
          onDisconnect: widget.onDisconnect);
    }
    final p = DolphinTechPalette.ofContext(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      widget.waiting,
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
            style: TextButton.styleFrom(foregroundColor: p.dangerText),
            onPressed: widget.onDisconnect,
            child: const Text(kNoPictureDisconnect)),
      ),
    ]);
  }
}
