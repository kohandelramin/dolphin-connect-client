import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'digits.dart';
import 'reconnect.dart';
import 'session_controls.dart';
import 'tech_card.dart';
import 'theme.dart';
import 'verify.dart';

typedef DolphinAccept = void Function(bool keyboard, bool clipboard, bool file);

/// The prompt a customer answers before a technician gets in. File transfer starts off. The name shown is the
/// one the portal vouches for ([verdict]); a peer the portal did not authorize gets no Accept button.
class DolphinAcceptView extends StatefulWidget {
  final TechVerdict verdict;
  final String peerName;
  final DolphinAccept onAccept;
  final VoidCallback onDeny;
  final bool showElevate;
  final DolphinAccept? onAcceptElevate;

  /// The support phone, for the D5 block (see [acceptAllowed]).
  final String phone;

  /// Plan 14 (B5): the verified technician's photo from the portal; shown only with a verified name.
  final Uint8List? photo;

  const DolphinAcceptView(
      {super.key,
      required this.verdict,
      required this.peerName,
      required this.onAccept,
      required this.onDeny,
      this.showElevate = false,
      this.onAcceptElevate,
      this.phone = '',
      this.photo});

  @override
  State<DolphinAcceptView> createState() => _DolphinAcceptViewState();
}

class _DolphinAcceptViewState extends State<DolphinAcceptView> {
  bool keyboard = true;
  bool clipboard = true;
  // ADR-0012: on by default, so copy and paste of files works without an extra step; the customer can untick it here
  // or switch it off in the session bar.
  bool file = true;

  Widget _toggle(String label, bool value, ValueChanged<bool> set) => FilterChip(
        label: Text(label),
        selected: value,
        onSelected: (v) => setState(() => set(v)),
        selectedColor: DolphinColors.azureTint,
        checkmarkColor: DolphinColors.azure,
      );

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final onAcceptElevate = widget.onAcceptElevate;
    final state = widget.verdict.state;
    final canAccept = acceptAllowed(widget.verdict);
    final (String title, String note, Color color, IconData icon) = switch (state) {
      TechCheck.verified => (
          '${widget.verdict.name.isEmpty ? widget.peerName : widget.verdict.name} از دلفین',
          'کارشناس تأییدشده‌ی دلفین می‌خواهد به این رایانه وصل شود',
          DolphinColors.azure,
          Icons.verified_user,
        ),
      TechCheck.checking => ('در حال بررسی هویت کارشناس…', 'چند لحظه صبر کنید', DolphinColors.muted, Icons.hourglass_top),
      TechCheck.unverifiable => (
          'پورتال دلفین در دسترس نیست؛ با دلفین تماس بگیرید.',
          widget.phone.isEmpty ? 'پشتیبانی دلفین' : 'پشتیبانی دلفین: ${faDigits(widget.phone)}',
          DolphinColors.danger,
          Icons.cloud_off,
        ),
      TechCheck.rejected => (
          'این اتصال از کارشناس دلفین نیست',
          'دلفین برای این رایانه اتصالی ثبت نکرده است؛ «رد» را بزنید',
          DolphinColors.danger,
          Icons.gpp_bad,
        ),
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (state == TechCheck.verified && widget.photo != null)
              DolphinTechAvatar(photo: widget.photo, radius: 32)
            else
              CircleAvatar(radius: 22, backgroundColor: color, child: Icon(icon, color: Colors.white)),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: state == TechCheck.rejected ? DolphinColors.dangerText : null)),
            Text(note, textAlign: TextAlign.center, style: const TextStyle(color: DolphinColors.muted)),
            const SizedBox(height: 12),
            if (canAccept)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _toggle('ماوس و صفحه‌کلید', keyboard, (v) => keyboard = v),
                  _toggle('کپی و چسباندن', clipboard, (v) => clipboard = v),
                  _toggle('انتقال فایل', file, (v) => file = v),
                ]),
            const SizedBox(height: 14),
            Row(children: [
              if (canAccept)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: DolphinColors.azure),
                    onPressed: () => widget.onAccept(keyboard, clipboard, file),
                    child: const Text('پذیرفتن'),
                  ),
                ),
              if (canAccept) const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: widget.onDeny, child: const Text('رد'))),
            ]),
            if (canAccept && widget.showElevate && onAcceptElevate != null)
              TextButton(
                onPressed: () => onAcceptElevate(keyboard, clipboard, file),
                child: const Text('پذیرفتن، با اجازه‌ی نصب برنامه'),
              ),
          ],
        ),
      ),
    );
  }
}

/// From the moment the customer accepted, read from the clock rather than counted in ticks (U7).
Duration sessionElapsed(DateTime? start, DateTime now) =>
    start == null || now.isBefore(start) ? Duration.zero : now.difference(start);

/// "۰۴:۱۲", or "۱:۰۲:۰۳" from an hour on. Persian digits via the shared [faDigits].
String sessionClock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return faDigits(h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}');
}

/// While a technician is connected: who, for how long, what he may do, «مکث» and the End button. Every permission stays
/// in the customer's hands for the whole session (SECURITY.md control 1; UX-13, DD-45): each has its own switch, and the
/// technician's strip shows the change at once. Made for the small window in the corner (DD-36,
/// [kDolphinSessionWindowSize]): the content scrolls and «پایان» stays pinned at the bottom, always visible.
class DolphinSessionView extends StatelessWidget {
  final String technician;
  final Duration elapsed;
  final bool keyboard;
  final bool clipboard;
  final bool file;

  /// D23: the same technician came back within 2 minutes of a drop; the badge says «دوباره وصل شد».
  final bool resumed;

  /// DD-46: the customer paused; the technician gets no picture and no input reaches the PC.
  final bool paused;

  /// Null hides «مکث» (a file-transfer tab has no picture to stop).
  final ValueChanged<bool>? onPause;

  /// DD-37: who blocked the customer's mouse and keyboard and since when ([inputOffDetail]); null while not blocked.
  final String? inputOff;

  /// `permission` is `keyboard`, `clipboard` or `file` (bind.cmSwitchPermission names).
  final void Function(String permission, bool enabled) onToggle;
  final VoidCallback onEnd;

  const DolphinSessionView(
      {super.key,
      required this.technician,
      required this.elapsed,
      required this.keyboard,
      required this.clipboard,
      required this.file,
      this.resumed = false,
      this.paused = false,
      this.onPause,
      this.inputOff,
      required this.onToggle,
      required this.onEnd});

  bool _value(String name) => switch (name) { 'keyboard' => keyboard, 'clipboard' => clipboard, _ => file };

  Widget _switch(String name, String label) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        title: Text(label, style: const TextStyle(fontSize: 13.5, color: DolphinColors.ink)),
        value: _value(name),
        onChanged: (v) => onToggle(name, v),
      );

  Widget _notice({required Color ground, required Color titleColor, required IconData icon, required String title,
          required List<String> lines}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(DolphinRadii.field)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: titleColor),
            const SizedBox(width: 6),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: titleColor))),
          ]),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: const TextStyle(fontSize: 12, height: 1.6, color: DolphinColors.ink)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final onPause = this.onPause;
    final inputOff = this.inputOff;
    final badge = paused ? '❚❚ $kDolphinPausedTitle' : (resumed ? '● $kDolphinReconnected' : '● در جلسه');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: DolphinColors.azureSoft, borderRadius: BorderRadius.circular(99)),
                  child: Text(badge,
                      style: const TextStyle(color: DolphinColors.azure, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
                const Spacer(),
                Text(sessionClock(elapsed),
                    textDirection: TextDirection.ltr, style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
              ]),
              const SizedBox(height: 6),
              Text(technician,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
              if (inputOff != null)
                _notice(
                    ground: DolphinColors.dangerSoft,
                    titleColor: DolphinColors.dangerText,
                    icon: Icons.mouse_outlined,
                    title: kDolphinInputOffTitle,
                    lines: [inputOff, kDolphinInputOffHint]),
              if (paused)
                _notice(
                    ground: DolphinColors.azureSoft,
                    titleColor: DolphinColors.azure,
                    icon: Icons.pause_circle_outline,
                    title: kDolphinPausedTitle,
                    lines: const [kDolphinPausedNote]),
              const SizedBox(height: 4),
              for (final (name, label) in kDolphinPermissionLabels) _switch(name, label),
              Text(onPause != null && !paused ? kDolphinPauseHint : 'هر کدام را خاموش کنید، کارشناس دیگر نمی‌تواند از آن استفاده کند.',
                  style: const TextStyle(color: DolphinColors.muted, fontSize: 11.5, height: 1.6)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Row(children: [
            if (onPause != null) ...[
              Expanded(
                child: paused
                    ? FilledButton.icon(
                        onPressed: () => onPause(false),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text(kDolphinResumeLabel))
                    : OutlinedButton.icon(
                        onPressed: () => onPause(true),
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text(kDolphinPauseLabel)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DolphinColors.danger),
                onPressed: onEnd,
                child: const Text('پایان'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// How long the ended screen waits for the portal's word before it says the technician ended the session (Plan 13 F5).
const kDolphinEndSettleMs = 4000;

/// The ended screen closes itself after this long, as «بستن» would (D15).
const kDolphinEndedAutoCloseMs = 60000;

enum DolphinEndReason { you, technician, portal }

/// Why the session ended (UX-6). The CM gets no reason from the connection (Plan 13 F4), so: our own «پایان» or «رد» is
/// "you"; a portal that no longer vouches for this peer (what it pushed with the cut) is "portal"; anything else, once
/// the portal had [kDolphinEndSettleMs] to say otherwise, is "technician" (a dropped link looks the same). Null meanwhile.
DolphinEndReason? endReason({required bool byCustomer, required TechCheck verdictNow, required int sinceEndMs}) {
  if (byCustomer) return DolphinEndReason.you;
  if (verdictNow == TechCheck.rejected) return DolphinEndReason.portal;
  if (sinceEndMs < kDolphinEndSettleMs) return null;
  return DolphinEndReason.technician;
}

/// The reason is fixed once it is known: a later portal push or an expired authorization must not rewrite what the
/// customer is reading. Only null (still settling) can become a value, once.
DolphinEndReason? latchReason(DolphinEndReason? current, DolphinEndReason? computed) => current ?? computed;

String endReasonText(DolphinEndReason r) => switch (r) {
      DolphinEndReason.you => 'شما پایان دادید.',
      DolphinEndReason.technician => 'اتصال کارشناس بسته شد.',
      DolphinEndReason.portal => 'پورتال دلفین این اتصال را قطع کرد.',
    };

/// UN-13: installing Dolphin software often needs a restart; the customer must know the way back.
const kDolphinRebootHint = 'اگر کارشناس خواست رایانه را دوباره روشن کنید، بعد از آن دلفین کانکت را باز کنید و دوباره تماس بگیرید.';

/// After a session ends, until the customer closes the window (or a minute passes, D15).
class DolphinEndedView extends StatefulWidget {
  final DolphinEndReason? reason;
  final VoidCallback onClose;
  const DolphinEndedView({super.key, required this.reason, required this.onClose});

  @override
  State<DolphinEndedView> createState() => _DolphinEndedViewState();
}

class _DolphinEndedViewState extends State<DolphinEndedView> {
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _autoClose = Timer(const Duration(milliseconds: kDolphinEndedAutoCloseMs), _close);
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  void _close() {
    _autoClose?.cancel();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final r = widget.reason;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('جلسه پایان یافت.', style: TextStyle(fontWeight: FontWeight.w700)),
          if (r != null) ...[
            const SizedBox(height: 4),
            Text(endReasonText(r), textAlign: TextAlign.center, style: const TextStyle(color: DolphinColors.muted)),
          ],
          const SizedBox(height: 6),
          const Text(kDolphinRebootHint,
              textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.6)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _close, child: const Text('بستن')),
        ]),
      ),
    );
  }
}
