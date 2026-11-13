import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'access_profile.dart';
import 'digits.dart';
import 'reconnect.dart';
import 'session_controls.dart';
import 'session_frame.dart';
import 'switch_row.dart';
import 'tech_card.dart';
import 'theme.dart';
import 'verify.dart';

export 'access_profile.dart' show DolphinGrant, DolphinProfile;

typedef DolphinAccept = void Function(DolphinGrant grant);

/// Under the technician's name in the prompt (design C2), with a ✓ mark drawn as an icon (Vazirmatn has no ✓).
const kVerifiedTechLine = 'کارشناس تأییدشده‌ی دلفین';
const kWantsToConnectLine = 'می‌خواهد به این رایانه وصل شود.';
const kAcceptLabel = 'پذیرفتن';
const kDenyLabel = 'رد';
const kAcceptElevateLabel = 'پذیرفتن، با اجازه‌ی نصب برنامه';

/// The first letter of a name for the round avatar when the portal sent no photo («ع» for «علی رضایی»).
String nameInitial(String name) {
  final t = name.trim();
  return t.isEmpty ? '' : String.fromCharCode(t.runes.first);
}

/// The prompt a customer answers before a technician gets in (C2, 320 × 520): who (the name the portal vouches for,
/// [verdict]), the two profiles «کامل» / «فقط تماشا», one switch per permission (sound off by default, DD-31), and
/// «پذیرفتن» / «رد». A peer the portal did not authorize gets no Accept button and no switches.
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

  /// DD-31: false when the organization does not offer the PC's sound (`remote-sound` hidden): no sound switch.
  final bool soundOffered;

  const DolphinAcceptView(
      {super.key,
      required this.verdict,
      required this.peerName,
      required this.onAccept,
      required this.onDeny,
      this.showElevate = false,
      this.onAcceptElevate,
      this.phone = '',
      this.photo,
      this.soundOffered = true});

  @override
  State<DolphinAcceptView> createState() => _DolphinAcceptViewState();
}

class _DolphinAcceptViewState extends State<DolphinAcceptView> {
  DolphinGrant _grant = DolphinGrant.initial;

  DolphinGrant get _granted => _grant.offered(sound: widget.soundOffered);

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: the customer's own look on any Windows theme

  Widget _who(String name) => Row(children: [
        if (widget.photo != null)
          DolphinTechAvatar(photo: widget.photo, radius: 22)
        else
          CircleAvatar(
            radius: 22,
            backgroundColor: DolphinColors.azureSoft,
            child: Text(nameInitial(name),
                style: TextStyle(color: DolphinColors.azureText, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
            Row(children: [
              Flexible(
                child: Text(kVerifiedTechLine,
                    style: TextStyle(fontSize: 12, color: DolphinColors.aquaText, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 3),
              Icon(Icons.verified, size: 14, color: DolphinColors.aquaText, semanticLabel: '✓'),
            ]),
          ]),
        ),
      ]);

  /// Checking, unverifiable or rejected: what holds, and only «رد».
  Widget _notVerified(TechCheck state) {
    final (String title, String note, Color color, IconData icon) = switch (state) {
      TechCheck.checking => ('در حال بررسی هویت کارشناس…', 'چند لحظه صبر کنید', DolphinColors.muted, Icons.hourglass_top),
      TechCheck.unverifiable => (
          'پورتال دلفین در دسترس نیست؛ با دلفین تماس بگیرید.',
          widget.phone.isEmpty ? 'پشتیبانی دلفین' : 'پشتیبانی دلفین: ${faDigits(widget.phone)}',
          DolphinColors.danger,
          Icons.cloud_off,
        ),
      _ => (
          'این اتصال از کارشناس دلفین نیست',
          'دلفین برای این رایانه اتصالی ثبت نکرده است؛ «رد» را بزنید',
          DolphinColors.danger,
          Icons.gpp_bad,
        ),
    };
    return Column(children: [
      const SizedBox(height: 12),
      CircleAvatar(radius: 24, backgroundColor: color, child: Icon(icon, color: DolphinColors.onFill)),
      const SizedBox(height: 12),
      Text(title,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: state == TechCheck.rejected ? DolphinColors.dangerText : DolphinColors.ink)),
      const SizedBox(height: 4),
      Text(note, textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 13, height: 1.6)),
    ]);
  }

  Widget _build(BuildContext context) {
    final onAcceptElevate = widget.onAcceptElevate;
    final state = widget.verdict.state;
    final canAccept = acceptAllowed(widget.verdict);
    final name = widget.verdict.name.isEmpty ? widget.peerName : widget.verdict.name;
    final profile = profileOf(_grant);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (state == TechCheck.verified) ...[
                _who(name),
                const SizedBox(height: 10),
                Text(kWantsToConnectLine, style: TextStyle(color: DolphinColors.ink, fontSize: 13.5)),
              ] else
                _notVerified(state),
              if (canAccept) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DolphinSegmented<DolphinProfile>(
                    keyPrefix: 'dolphin-profile',
                    options: const [(DolphinProfile.full, kProfileFullLabel), (DolphinProfile.viewOnly, kProfileViewOnlyLabel)],
                    selected: profile == DolphinProfile.custom ? null : profile,
                    onSelected: (p) => setState(() => _grant = grantFor(p, _grant)),
                  ),
                ),
                const SizedBox(height: 6),
                for (final (permission, label) in grantLabels(sound: widget.soundOffered))
                  DolphinSwitchRow(
                    switchKey: ValueKey('dolphin-grant-$permission'),
                    label: label,
                    value: _grant.of(permission),
                    onChanged: (v) => setState(() => _grant = _grant.withPermission(permission, v)),
                  ),
                const SizedBox(height: 4),
                Text(kGrantOnlyYouLine, style: TextStyle(color: DolphinColors.muted, fontSize: 11.5, height: 1.6)),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              if (canAccept) ...[
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('dolphin-accept'),
                    style: FilledButton.styleFrom(
                        backgroundColor: DolphinColors.accentFill, foregroundColor: DolphinColors.onFill),
                    onPressed: () => widget.onAccept(_granted),
                    child: const Text(kAcceptLabel),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('dolphin-deny'),
                  style: OutlinedButton.styleFrom(foregroundColor: DolphinColors.ink, backgroundColor: DolphinColors.surface),
                  onPressed: widget.onDeny,
                  child: const Text(kDenyLabel),
                ),
              ),
            ]),
            if (canAccept && widget.showElevate && onAcceptElevate != null)
              TextButton(
                onPressed: () => onAcceptElevate(_granted),
                style: TextButton.styleFrom(foregroundColor: DolphinColors.azureText),
                child: const Text(kAcceptElevateLabel),
              ),
          ]),
        ),
      ]),
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

/// The session window's title (C3): «علی رضایی وصل است».
String connectedTitle(String technician) => '$technician وصل است';

/// While a technician is connected (C3, the small window in the corner, DD-36 [kDolphinSessionWindowSize]): who and
/// for how long, one switch per permission (SECURITY.md control 1; UX-13, DD-45: every permission stays in the
/// customer's hands, and the technician's strip shows a change at once), «کادر رنگی دور صفحه», «مکث» and «پایان».
/// The content scrolls; «مکث» and «پایان» stay pinned at the bottom, always visible.
class DolphinSessionView extends StatelessWidget {
  final String technician;
  final Duration elapsed;
  final bool keyboard;
  final bool clipboard;
  final bool file;

  /// DD-31: the PC's sound (upstream's audio permission); the switch shows only when [soundOffered].
  final bool audio;
  final bool soundOffered;

  /// D23: the same technician came back within 2 minutes of a drop; the badge says «دوباره وصل شد».
  final bool resumed;

  /// DD-46: the customer paused; the technician gets no picture and no input reaches the PC.
  final bool paused;

  /// Null hides «مکث» (a file-transfer tab has no picture to stop).
  final ValueChanged<bool>? onPause;

  /// DD-37: who blocked the customer's mouse and keyboard and since when ([inputOffDetail]); null while not blocked.
  final String? inputOff;

  /// `permission` is `keyboard`, `clipboard`, `file` or `audio` (bind.cmSwitchPermission names).
  final void Function(String permission, bool enabled) onToggle;
  final VoidCallback onEnd;

  /// DD-29: opens or closes the chat beside the session; null hides «گفتگو» (a file-transfer tab has no chat).
  final VoidCallback? onChat;

  /// C3: «کادر رنگی دور صفحه» (session_frame.dart); a null [onFrame] hides the switch.
  final bool frame;
  final ValueChanged<bool>? onFrame;

  const DolphinSessionView(
      {super.key,
      required this.technician,
      required this.elapsed,
      required this.keyboard,
      required this.clipboard,
      required this.file,
      this.audio = false,
      this.soundOffered = false,
      this.resumed = false,
      this.paused = false,
      this.onPause,
      this.inputOff,
      required this.onToggle,
      required this.onEnd,
      this.onChat,
      this.frame = false,
      this.onFrame});

  bool _value(String name) => switch (name) {
        'keyboard' => keyboard,
        'clipboard' => clipboard,
        'audio' => audio,
        _ => file,
      };

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
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: titleColor, fontSize: 13))),
          ]),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: TextStyle(fontSize: 12, height: 1.6, color: DolphinColors.ink)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: the customer's own look on any Windows theme

  Widget _build(BuildContext context) {
    final onPause = this.onPause;
    final onFrame = this.onFrame;
    final inputOff = this.inputOff;
    final badge = paused ? '❚❚ $kDolphinPausedTitle' : (resumed ? '● $kDolphinReconnected' : null);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(connectedTitle(technician),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                ),
                const SizedBox(width: 6),
                Container(
                  key: const ValueKey('dolphin-session-clock'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(color: DolphinColors.azureSoft, borderRadius: BorderRadius.circular(99)),
                  child: Text(sessionClock(elapsed),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: DolphinColors.azureText, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]),
              if (badge != null || onChat != null)
                Row(children: [
                  Expanded(
                    child: badge == null
                        ? const SizedBox.shrink()
                        : Text(badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: DolphinColors.azureText, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  if (onChat != null)
                    Flexible(
                      child: TextButton.icon(
                        key: const ValueKey('dolphin-session-chat'),
                        onPressed: onChat,
                        style: TextButton.styleFrom(
                            foregroundColor: DolphinColors.azureText,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 4)),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text(kDolphinChatLabel,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                ]),
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
                    titleColor: DolphinColors.azureText,
                    icon: Icons.pause_circle_outline,
                    title: kDolphinPausedTitle,
                    lines: const [kDolphinPausedNote]),
              const SizedBox(height: 4),
              for (final (name, label) in grantLabels(sound: soundOffered))
                DolphinSwitchRow(
                  switchKey: ValueKey('dolphin-session-$name'),
                  label: label,
                  value: _value(name),
                  onChanged: (v) => onToggle(name, v),
                ),
              if (onFrame != null)
                DolphinSwitchRow(
                  switchKey: const ValueKey('dolphin-session-frame'),
                  label: kFrameLabel,
                  value: frame,
                  onChanged: onFrame,
                ),
              const SizedBox(height: 2),
              Text(onPause != null && !paused ? kDolphinPauseHint : 'هر کدام را خاموش کنید، کارشناس دیگر نمی‌تواند از آن استفاده کند.',
                  style: TextStyle(color: DolphinColors.muted, fontSize: 11.5, height: 1.6)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Row(children: [
            if (onPause != null) ...[
              Expanded(
                child: paused
                    ? FilledButton.icon(
                        key: const ValueKey('dolphin-session-resume'),
                        onPressed: () => onPause(false),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text(kDolphinResumeLabel))
                    : OutlinedButton.icon(
                        key: const ValueKey('dolphin-session-pause'),
                        style: OutlinedButton.styleFrom(backgroundColor: DolphinColors.surface),
                        onPressed: () => onPause(true),
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text(kDolphinPauseLabel)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('dolphin-session-end'),
                style: FilledButton.styleFrom(backgroundColor: DolphinColors.danger, foregroundColor: DolphinColors.onFill),
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


/// DD-29: the customer's button for the chat with the technician.
const kDolphinChatLabel = 'گفتگو با کارشناس';

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
      child: Container(
        color: DolphinColors.ground,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, size: 36, color: DolphinColors.aquaText),
          const SizedBox(height: 8),
          Text('جلسه پایان یافت.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: DolphinColors.ink)),
          if (r != null) ...[
            const SizedBox(height: 4),
            Text(endReasonText(r), textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted)),
          ],
          const SizedBox(height: 6),
          Text(kDolphinRebootHint,
              textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.6)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _close, child: const Text('بستن')),
        ]),
      ),
    );
  }
}
