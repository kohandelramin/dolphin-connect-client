import 'dart:async';

import 'package:flutter/material.dart';

import 'tech_theme.dart';
import 'theme_tokens.dart';

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

// Plan 19 (T7): the connection's stages have names, so the technician knows what the window waits for.
const kStageSecure = 'آماده‌سازی اتصال امن';
String stageWaiting(String peer) => peer.trim().isEmpty ? 'در انتظار تصویر' : 'در انتظار تصویر از ${peer.trim()}';

/// After this long without a picture the window says to check both sides' internet (T7).
const kDolphinSlowPictureAfter = Duration(seconds: 60);
const kSlowPictureText = 'تا ۶۰ ثانیه تصویری نیامد: اینترنت هر دو طرف را بررسی کنید.';
const kSlowKeepWaiting = 'ادامه‌ی انتظار';
const kSlowSendCad = 'ارسال Ctrl+Alt+Del';

/// T7: «✓ آماده‌سازی اتصال امن» (done once the window waits for the picture) and «● در انتظار تصویر از …».
class DolphinConnectStages extends StatelessWidget {
  final String peer;
  const DolphinConnectStages({super.key, this.peer = ''});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    Widget chip(String text, {required bool done}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: done ? p.fill : p.accentSoft, borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(done ? Icons.check : Icons.circle, size: done ? 14 : 8, color: done ? Colors.white : p.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: done ? Colors.white : p.accent)),
            ),
          ]),
        );
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        key: const ValueKey('dolphin-connect-stages'),
        spacing: 6,
        runSpacing: 6,
        children: [chip(kStageSecure, done: true), chip(stageWaiting(peer), done: false)],
      ),
    );
  }
}

/// T7 after [kDolphinSlowPictureAfter]: the stages, the network line and «ادامه‌ی انتظار» / «ارسال Ctrl+Alt+Del» / «قطع».
class DolphinSlowPicture extends StatelessWidget {
  final String peer;
  final bool canCtrlAltDel;
  final VoidCallback? onCtrlAltDel;
  final VoidCallback onKeepWaiting;
  final VoidCallback onDisconnect;
  const DolphinSlowPicture(
      {super.key,
      this.peer = '',
      required this.canCtrlAltDel,
      this.onCtrlAltDel,
      required this.onKeepWaiting,
      required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final cad = canCtrlAltDel && onCtrlAltDel != null;
    return DolphinTechTheme(
      paint: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
            key: const ValueKey('dolphin-slow-picture'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DolphinConnectStages(peer: peer),
              const SizedBox(height: 12),
              Text(kSlowPictureText, textAlign: TextAlign.center, style: TextStyle(color: p.ink, height: 1.7)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                OutlinedButton(onPressed: onKeepWaiting, child: const Text(kSlowKeepWaiting)),
                if (cad) OutlinedButton(onPressed: onCtrlAltDel, child: const Text(kSlowSendCad)),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: DolphinTheme.of(p.brightness).dangerFill),
                    onPressed: onDisconnect,
                    child: const Text(kNoPictureDisconnect)),
              ]),
            ]),
      ),
    );
  }
}

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

  /// T7: the PC's name for «در انتظار تصویر از …», and when to show the network line.
  final String peer;
  final Duration slowAfter;
  final bool canCtrlAltDel;
  final bool? installed;
  final VoidCallback? onCtrlAltDel;
  final VoidCallback onDisconnect;
  const DolphinWaitingForPicture(
      {super.key,
      required this.waiting,
      this.after = kDolphinNoPictureAfter,
      this.peer = '',
      this.slowAfter = kDolphinSlowPictureAfter,
      required this.canCtrlAltDel,
      this.installed,
      this.onCtrlAltDel,
      required this.onDisconnect});

  @override
  State<DolphinWaitingForPicture> createState() => _DolphinWaitingForPictureState();
}

class _DolphinWaitingForPictureState extends State<DolphinWaitingForPicture> {
  Timer? _timer;
  Timer? _slowTimer;
  bool _help = false;
  bool _slow = false;

  void _wait() {
    _timer?.cancel();
    if (_help) setState(() => _help = false);
    _timer = Timer(widget.after, () {
      if (mounted) setState(() => _help = true);
    });
  }

  /// T7 «ادامه‌ی انتظار»: back to the plain wait; the network line again after another slowAfter.
  void _keepWaiting() {
    _slowTimer?.cancel();
    if (_slow) setState(() => _slow = false);
    _slowTimer = Timer(widget.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
    _wait();
  }

  @override
  void initState() {
    super.initState();
    _keepWaiting();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_slow) {
      return DolphinSlowPicture(
          peer: widget.peer,
          canCtrlAltDel: widget.canCtrlAltDel,
          onCtrlAltDel: widget.onCtrlAltDel,
          onKeepWaiting: _keepWaiting,
          onDisconnect: widget.onDisconnect);
    }
    if (_help) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DolphinTechTheme(paint: false, child: DolphinConnectStages(peer: widget.peer)),
        const SizedBox(height: 12),
        DolphinNoPictureHelp(
            canCtrlAltDel: widget.canCtrlAltDel,
            installed: widget.installed,
            onCtrlAltDel: widget.onCtrlAltDel,
            onWait: _wait,
            onDisconnect: widget.onDisconnect),
      ]);
    }
    final p = DolphinTechPalette.ofContext(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DolphinTechTheme(paint: false, child: DolphinConnectStages(peer: widget.peer)),
      const SizedBox(height: 12),
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
