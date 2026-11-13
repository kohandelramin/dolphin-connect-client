import 'package:flutter/material.dart';

import 'digits.dart';
import 'tech_theme.dart';
import 'theme.dart';

/// Plan 18 Phase 5 (DD-11): restart the customer's PC into Safe Mode with networking, and back. Pure rules and views,
/// so they are tested; the wiring is safe_mode_hooks.dart, the customer's PC src/dolphin_safe_mode_core.rs.
///
/// The technician's toolbar asks the customer's PC over the session (`session_set_common` key [kDolphinSafeModeKey],
/// sent as the existing `Misc::PluginRequest`); never upstream's remote restart (`enable-remote-restart` stays "N").
/// The customer sees [kDolphinRestartSecs] seconds of notice with «لغو» first.

/// `session_set_common` key on the technician's side, and the `MessageBox` type of every answer from the PC.
const kDolphinSafeModeKey = 'dolphin-safe-mode';

/// The customer window's «لغو» (bind.cmSwitchPermission name; src/dolphin_safe_mode_core.rs CM_CANCEL).
const kDolphinRestartCancel = 'dolphin-restart-cancel';

/// `platform_additions` key: true while the customer's PC runs in Safe Mode.
const kDolphinSafeModeAddition = 'dolphin_safe_mode';

/// `platform_additions` key: true when the customer's PC takes «ری‌استارت در حالت امن» (its organization's `safe-mode`
/// switch is not hidden, the app is installed, the service runs it). The technician app has no heartbeat, so it never
/// knows the switches itself; the customer's PC decides, and decides again when the request comes.
const kDolphinSafeModeOffered = 'dolphin_safe_mode_offered';

/// The notice the customer gets (src/dolphin_safe_mode_core.rs NOTICE_SECS).
const kDolphinRestartSecs = 20;

/// How long the technician's app waits for the PC's first answer before saying the app may be old.
const kDolphinSafeModeReplyWait = Duration(seconds: 10);

enum DolphinRestartKind { safe, normal }

/// The value sent with [kDolphinSafeModeKey], and the customer window's record (`Client.dolphin_restart`).
String restartCode(DolphinRestartKind k) => k == DolphinRestartKind.safe ? 'safe' : 'normal';

DolphinRestartKind? restartKindFrom(String? code) => switch (code) {
      'safe' => DolphinRestartKind.safe,
      'normal' => DolphinRestartKind.normal,
      _ => null,
    };

// ---- the technician ----

const kSafeModeAskTitle = 'ری‌استارت در حالت امن';
const kSafeModeReturnTitle = 'بازگشت به حالت عادی';
const kSafeModeAskLines = [
  'رایانه‌ی مشتری در حالت امن (Safe Mode) با شبکه دوباره راه‌اندازی می‌شود.',
  'مشتری ۲۰ ثانیه فرصت دارد «لغو» را بزند. پس از ورود مشتری به ویندوز، دلفین کانکت خودش باز می‌شود و دوباره وصل می‌شوید.',
  'ری‌استارت بعدی رایانه را به حالت عادی برمی‌گرداند.',
];
const kSafeModeReturnLines = [
  'رایانه‌ی مشتری دوباره راه‌اندازی می‌شود و به حالت عادی برمی‌گردد.',
  'مشتری ۲۰ ثانیه فرصت دارد «لغو» را بزند.',
];
const kSafeModeRestart = 'ری‌استارت';
const kSafeModeCancel = 'انصراف';
const kSafeModeOk = 'باشه';
const kSafeModeNoReply = 'برنامه‌ی مشتری جواب نداد؛ شاید نسخه‌ی آن قدیمی است.';

/// The toolbar entry for this session: «بازگشت به حالت عادی» on a PC that says it runs in Safe Mode (whatever its
/// switch says, so a PC can always come back), «ری‌استارت در حالت امن» when the PC said at login that it takes it,
/// otherwise none (an older customer app says neither).
DolphinRestartKind? safeModeEntry({required bool? peerInSafeMode, required bool? peerOffers}) {
  if (peerInSafeMode == true) return DolphinRestartKind.normal;
  return peerOffers == true ? DolphinRestartKind.safe : null;
}

/// The PC's answer as the technician reads it.
enum SafeModeTone { info, ok, warn }

class SafeModeAnswer {
  final SafeModeTone tone;
  final String text;

  /// The customer is reading the notice; another answer follows.
  final bool waiting;
  const SafeModeAnswer(this.tone, this.text, {this.waiting = false});
}

/// The answer in a `MessageBox` of type [kDolphinSafeModeKey] (title the code, text the Persian line); null for
/// anything else, which upstream handles. A text that is not a short line is replaced by a plain one.
SafeModeAnswer? safeModeAnswerFromMsgBox(dynamic type, dynamic title, dynamic text) {
  if (type != kDolphinSafeModeKey || title is! String) return null;
  final tone = title.startsWith('restarting-')
      ? SafeModeTone.ok
      : title.startsWith('notice-')
          ? SafeModeTone.info
          : SafeModeTone.warn;
  final line = text is String ? text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim() : '';
  final shown = line.isEmpty || line.length > 200
      ? (tone == SafeModeTone.warn ? 'ری‌استارت انجام نشد.' : 'انجام شد.')
      : line;
  return SafeModeAnswer(tone, shown, waiting: title.startsWith('notice-'));
}

/// The technician's confirmation before asking the PC.
class DolphinSafeModeAskView extends StatelessWidget {
  final DolphinRestartKind kind;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const DolphinSafeModeAskView({super.key, required this.kind, required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final safe = kind == DolphinRestartKind.safe;
    return DolphinTechTheme(
      paint: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(safe ? Icons.health_and_safety_outlined : Icons.settings_backup_restore, color: p.accent),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(safe ? kSafeModeAskTitle : kSafeModeReturnTitle,
                      style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            for (final l in safe ? kSafeModeAskLines : kSafeModeReturnLines)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l, style: TextStyle(color: p.ink, height: 1.6)),
              ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(
                  key: const ValueKey('dolphin-safe-mode-confirm'), onPressed: onConfirm, child: const Text(kSafeModeRestart)),
              OutlinedButton(onPressed: onCancel, child: const Text(kSafeModeCancel)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The PC's answer, in the technician's dialog.
class DolphinSafeModeAnswerView extends StatelessWidget {
  final SafeModeAnswer answer;
  final VoidCallback onClose;
  const DolphinSafeModeAnswerView({super.key, required this.answer, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final (IconData icon, Color color) = switch (answer.tone) {
      SafeModeTone.ok => (Icons.restart_alt, p.okText),
      SafeModeTone.info => (Icons.hourglass_top, p.accent),
      SafeModeTone.warn => (Icons.info_outline, p.warnText),
    };
    return DolphinTechTheme(
      paint: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(answer.text, style: TextStyle(color: p.ink, height: 1.6))),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(onPressed: onClose, child: const Text(kSafeModeOk)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---- the customer ----

/// Seconds of notice left, from the moment the window first showed it.
int restartSecondsLeft(DateTime seenAt, DateTime now) {
  final gone = now.difference(seenAt).inSeconds;
  if (gone < 0) return kDolphinRestartSecs;
  return gone >= kDolphinRestartSecs ? 0 : kDolphinRestartSecs - gone;
}

const kRestartNoticeSafeTitle = 'ری‌استارت در حالت امن';
const kRestartNoticeNormalTitle = 'بازگشت به حالت عادی';
const kRestartNoticeSafe =
    'کارشناس دلفین می‌خواهد رایانه را در حالت امن (Safe Mode) با شبکه دوباره راه‌اندازی کند. کارهای باز را ذخیره کنید.';
const kRestartNoticeNormal =
    'کارشناس دلفین می‌خواهد رایانه را به حالت عادی دوباره راه‌اندازی کند. کارهای باز را ذخیره کنید.';
const kRestartNoticeSafeAfter = 'پس از ورود به ویندوز، دلفین کانکت خودش باز می‌شود.';
const kRestartNoticeNow = 'رایانه در حال راه‌اندازی دوباره است…';
const kRestartCancel = 'لغو';

String restartCountdown(int seconds) => seconds <= 0 ? kRestartNoticeNow : '${faDigits('$seconds')} ثانیه‌ی دیگر';

/// The customer's notice, in place of the session view while it counts down. «لغو» tells the technician.
class DolphinRestartNoticeView extends StatelessWidget {
  final DolphinRestartKind kind;
  final int secondsLeft;
  final VoidCallback? onCancel;
  const DolphinRestartNoticeView({super.key, required this.kind, required this.secondsLeft, required this.onCancel});

  @override
  Widget build(BuildContext context) => DolphinLight(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final safe = kind == DolphinRestartKind.safe;
    final done = secondsLeft <= 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.restart_alt, color: DolphinColors.amberText),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(safe ? kRestartNoticeSafeTitle : kRestartNoticeNormalTitle,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DolphinColors.ink))),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: DolphinColors.amberSoft, borderRadius: BorderRadius.circular(DolphinRadii.field)),
                child: Text(safe ? kRestartNoticeSafe : kRestartNoticeNormal,
                    style: TextStyle(fontSize: 13, height: 1.7, color: DolphinColors.amberText)),
              ),
              const SizedBox(height: 12),
              Text(restartCountdown(secondsLeft),
                  key: const ValueKey('dolphin-restart-countdown'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: done ? 15 : 20, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
              if (safe) ...[
                const SizedBox(height: 8),
                Text(kRestartNoticeSafeAfter,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.6, color: DolphinColors.muted)),
              ],
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('dolphin-restart-cancel'),
              style: FilledButton.styleFrom(backgroundColor: DolphinColors.danger),
              onPressed: done ? null : onCancel,
              child: const Text(kRestartCancel),
            ),
          ),
        ),
      ]),
    );
  }
}

const kSafeModeBannerTitle = 'حالت امن (Safe Mode)';
const kSafeModeBannerLine = 'رایانه برای رفع مشکل در حالت امن روشن شده است. ری‌استارت بعدی آن را به حالت عادی برمی‌گرداند.';
const kSafeModeBannerReturn = 'بازگشت به حالت عادی';
const kSafeModeReturnConfirm = 'رایانه دوباره راه‌اندازی می‌شود و به حالت عادی برمی‌گردد. کارهای باز را ذخیره کنید.';

/// The customer's home in Safe Mode: what is going on and the way back.
class DolphinSafeModeBanner extends StatelessWidget {
  final VoidCallback? onReturn;

  /// The last answer to «بازگشت به حالت عادی» ([customerReturnText]), shown under the button.
  final String? note;
  const DolphinSafeModeBanner({super.key, required this.onReturn, this.note});

  @override
  Widget build(BuildContext context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DolphinColors.amberSoft,
              borderRadius: BorderRadius.circular(DolphinRadii.field),
              border: Border.all(color: DolphinColors.amberText.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.health_and_safety_outlined, size: 18, color: DolphinColors.amberText),
                SizedBox(width: 6),
                Expanded(
                    child: Text(kSafeModeBannerTitle,
                        style: TextStyle(fontWeight: FontWeight.w800, color: DolphinColors.amberText))),
              ]),
              const SizedBox(height: 4),
              Text(kSafeModeBannerLine, style: TextStyle(fontSize: 12, height: 1.6, color: DolphinColors.ink)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('dolphin-safe-mode-return'),
                onPressed: onReturn,
                icon: const Icon(Icons.settings_backup_restore, size: 18),
                label: const Text(kSafeModeBannerReturn),
              ),
              if (note != null && note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(note!, style: TextStyle(fontSize: 12, height: 1.6, color: DolphinColors.ink)),
                ),
            ]),
          ),
        ),
      );
}

/// The customer's confirmation before the restart.
class DolphinSafeModeReturnConfirm extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const DolphinSafeModeReturnConfirm({super.key, required this.onConfirm, required this.onCancel});

  @override
  Widget build(BuildContext context) => DolphinLight(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(kSafeModeBannerReturn,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
              const SizedBox(height: 8),
              Text(kSafeModeReturnConfirm, style: TextStyle(height: 1.7, color: DolphinColors.ink)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: FilledButton(
                        key: const ValueKey('dolphin-safe-mode-return-confirm'),
                        onPressed: onConfirm,
                        child: const Text(kSafeModeRestart))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: onCancel, child: const Text(kSafeModeCancel))),
              ]),
            ]),
          ),
        ),
      );
}

/// What the customer reads after «بازگشت به حالت عادی» (the service's answer, src/dolphin_safe_mode_core.rs
/// ReturnAnswer, or "no-service" when the service did not answer).
String customerReturnText(String code, String phone) => switch (code) {
      'restarting' => 'رایانه چند ثانیه‌ی دیگر دوباره راه‌اندازی می‌شود.',
      'not-safe' => 'رایانه در حالت امن نیست.',
      'busy' => 'ری‌استارت در راه است.',
      _ => 'سرویس دلفین کانکت پاسخ نداد. رایانه را از منوی Start دوباره راه‌اندازی کنید؛ اگر باز هم در حالت امن روشن '
          'شد با پشتیبانی دلفین تماس بگیرید: ${faDigits(phone)}',
    };
