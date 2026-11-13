import 'package:flutter/material.dart';

import 'digits.dart';
import 'tech_theme.dart';
import 'theme.dart';

/// Plan 19 (D1–D2): «ارائه دمو», the customer watches the technician's screen. Pure rules and views, so they are tested;
/// the wiring is demo_hooks.dart, the rules on both PCs src/dolphin_demo_core.rs.
///
/// The technician's session asks the customer's PC over the session (`session_set_common` key [kDolphinDemoKey], sent
/// as the existing `Misc::PluginRequest`); every answer comes back as a `MessageBox` of the same type. The customer
/// presses «دیدن» first, then their app connects back to the technician's over upstream's switch sides and shows his
/// screen, view only.

/// `session_set_common` key on the technician's side, and the `MessageBox` type of every answer from the PC.
const kDolphinDemoKey = 'dolphin-demo';

/// Technician's session: forget the wait (src/dolphin_demo_core.rs SESSION_CANCEL).
const kDolphinDemoCancelKey = 'dolphin-demo-cancel';

/// The dashboard's intent for the next session window (`main_set_common`), taken once when the window opens.
const kDolphinDemoIntentKey = 'dolphin-demo-intent';

/// `platform_additions` key of the customer PC: true where the demo can show, false on the x86 (Windows 7/8) build.
const kDolphinDemoAddition = 'dolphin_demo';

/// `platform_additions` key of the technician PC on the demo connection: "all" when he allowed all his screens.
const kDolphinDemoScreensAddition = 'dolphin_demo_screens';

/// The customer window's «دیدن» / «نه» (bind.cmSwitchPermission name; src/dolphin_demo_core.rs CM_ANSWER).
const kDolphinDemoAnswer = 'dolphin-demo-answer';

/// How long the technician's app waits for the PC's first answer before saying the app may be old.
const kDolphinDemoReplyWait = Duration(seconds: 10);

/// How long the customer has to answer (src/dolphin_demo_core.rs ASK_SECS).
const kDolphinDemoAskSecs = 60;

/// The value of [kDolphinDemoKey]: whether the technician allowed all his screens («همه‌ی صفحه‌های من»).
String demoScreensValue(bool all) => all ? 'all' : 'primary';

/// The dashboard's intent: `<screens>:<peer id>`.
String demoIntentValue(String peerId, bool all) => '${demoScreensValue(all)}:${peerId.replaceAll(' ', '')}';

// ---- the technician ----

const kDemoConfirmLine = 'مشتری صفحه‌ی شما را می‌بیند ولی نمی‌تواند چیزی را کنترل کند.';
const kDemoAllScreens = 'همه‌ی صفحه‌های من';
const kDemoAllScreensOff = 'فقط صفحه‌ی اصلی شما نشان داده می‌شود.';
const kDemoAllScreensOn = 'مشتری می‌تواند همه‌ی صفحه‌های شما را ببیند.';
const kDemoStart = 'شروع دمو';
const kDemoCancel = 'انصراف';
const kDemoWaitCancel = 'لغو';
const kDemoClose = 'بستن';
const kDemoEnd = 'پایان دمو';
const kDemoAsking = 'از مشتری پرسیده می‌شود…';
const kDemoUnsupported = 'دمو برای این رایانه (ویندوز ۷/۸) در دسترس نیست';
const kDemoOldApp = 'برنامه‌ی دلفین کانکت این رایانه قدیمی است؛ پس از به‌روزرسانی آن دوباره امتحان کنید.';
const kDemoNoReply = 'برنامه‌ی این رایانه جواب نداد؛ شاید نسخه‌ی آن قدیمی است.';
const kDemoDropped = 'ارتباط با رایانه‌ی مشتری قطع شد؛ دمو شروع نشد.';

String demoConfirmTitle(String peer) => 'ارائه دمو به $peer';

/// What the customer's PC said at login about the demo.
enum DemoCapability { yes, x86, old }

DemoCapability demoCapability(dynamic addition) => switch (addition) {
      true => DemoCapability.yes,
      false => DemoCapability.x86,
      _ => DemoCapability.old,
    };

/// The PC's answer as the technician reads it.
class DemoAnswer {
  final String code;
  final String text;

  /// The prompt is on the customer's screen; another answer follows.
  final bool waiting;

  /// «دیدن»: the technician's session window closes, the red bar comes when the customer's PC connects back.
  final bool accepted;

  /// The customer's PC ends this connection right after this answer.
  final bool closes;
  const DemoAnswer(this.code, this.text, {this.waiting = false, this.accepted = false, this.closes = false});
}

const _fallback = {
  'asking': 'از مشتری پرسیده شد؛ منتظر «دیدن» است.',
  'accepted': 'مشتری «دیدن» را زد.',
  'refused': 'مشتری دمو را نپذیرفت.',
  'no-answer': 'مشتری جواب نداد.',
  'unsupported': kDemoUnsupported,
};

/// The answer in a `MessageBox` of type [kDolphinDemoKey] (title the code, text the Persian line); null for anything
/// else, which upstream handles. A text that is not a short line is replaced by a plain one.
DemoAnswer? demoAnswerFromMsgBox(dynamic type, dynamic title, dynamic text) {
  if (type != kDolphinDemoKey || title is! String) return null;
  final line = text is String ? text.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim() : '';
  final shown = line.isEmpty || line.length > 200 ? (_fallback[title] ?? 'دمو شروع نشد.') : line;
  return DemoAnswer(title, shown,
      waiting: title == 'asking',
      accepted: title == 'accepted',
      closes: title == 'accepted' || title == 'refused' || title == 'no-answer');
}

/// «۰۲:۱۴», or «۱:۰۲:۱۴» past an hour.
String demoElapsed(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  final text = s >= 3600 ? '${s ~/ 3600}:${two(s % 3600 ~/ 60)}:${two(s % 60)}' : '${two(s ~/ 60)}:${two(s % 60)}';
  return faDigits(text);
}

/// The red bar's line (D1). The PC's name is isolated (FSI … PDI), so a Latin name does not pull the time into its
/// own left-to-right run.
String demoBarText(String peer, Duration elapsed) =>
    'در حال نمایش صفحه‌ی شما به \u2068$peer\u2069 · ${demoElapsed(elapsed)}';

/// The technician's confirmation before the demo (D1): which PC, that the customer only watches, his screens.
class DolphinDemoConfirmView extends StatelessWidget {
  final String peerName;
  final bool allScreens;
  final ValueChanged<bool> onAllScreens;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  const DolphinDemoConfirmView(
      {super.key,
      required this.peerName,
      required this.allScreens,
      required this.onAllScreens,
      required this.onStart,
      required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    return DolphinTechTheme(
      paint: false,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.co_present_outlined, color: p.accent),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(demoConfirmTitle(peerName),
                      style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 10),
            Text(kDemoConfirmLine, style: TextStyle(color: p.ink, height: 1.6)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kDemoAllScreens, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                  Text(allScreens ? kDemoAllScreensOn : kDemoAllScreensOff,
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.5)),
                ]),
              ),
              Switch(
                  key: const ValueKey('dolphin-demo-all-screens'),
                  value: allScreens,
                  activeColor: p.fill,
                  onChanged: onAllScreens),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton(key: const ValueKey('dolphin-demo-start'), onPressed: onStart, child: const Text(kDemoStart)),
              OutlinedButton(onPressed: onCancel, child: const Text(kDemoCancel)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The technician's session while the customer is asked; [onCancel] gives the wait up.
class DolphinDemoWaitView extends StatelessWidget {
  final String text;
  final VoidCallback onCancel;
  const DolphinDemoWaitView({super.key, required this.text, required this.onCancel});

  @override
  Widget build(BuildContext context) => _techLine(context, Icons.hourglass_top, null, text,
      OutlinedButton(key: const ValueKey('dolphin-demo-wait-cancel'), onPressed: onCancel, child: const Text(kDemoWaitCancel)));
}

/// The PC's last word in the technician's session; «بستن» closes the session window (a demo never becomes a control
/// session).
class DolphinDemoAnswerView extends StatelessWidget {
  final String text;
  final VoidCallback onClose;
  const DolphinDemoAnswerView({super.key, required this.text, required this.onClose});

  @override
  Widget build(BuildContext context) => _techLine(context, Icons.info_outline, true, text,
      OutlinedButton(key: const ValueKey('dolphin-demo-close'), onPressed: onClose, child: const Text(kDemoClose)));
}

Widget _techLine(BuildContext context, IconData icon, bool? warn, String text, Widget button) {
  final p = DolphinTechPalette.ofContext(context);
  return DolphinTechTheme(
    paint: false,
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: warn == true ? p.warnText : p.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(text, key: const ValueKey('dolphin-demo-text'), style: TextStyle(color: p.ink, height: 1.6))),
          ]),
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerEnd, child: button),
        ]),
      ),
    ),
  );
}

/// The red bar on top of the technician's screen while the customer watches (D1). Always red, whatever the theme: it
/// must never be missed.
class DolphinDemoBar extends StatelessWidget {
  final String peerName;
  final Duration elapsed;
  final VoidCallback onEnd;
  const DolphinDemoBar({super.key, required this.peerName, required this.elapsed, required this.onEnd});

  static const red = kDolphinDemoRed;

  @override
  Widget build(BuildContext context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            color: red,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              const Icon(Icons.circle, size: 10, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(demoBarText(peerName, elapsed),
                    key: const ValueKey('dolphin-demo-bar-text'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('dolphin-demo-bar-end'),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: red,
                    minimumSize: const Size(64, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: onEnd,
                child: const Text(kDemoEnd),
              ),
            ]),
          ),
        ),
      );
}

// ---- the customer ----

const kDemoAskHint = 'شما فقط می‌بینید؛ کسی به رایانه‌ی شما دسترسی تازه پیدا نمی‌کند.';
const kDemoSee = 'دیدن';
const kDemoNo = 'نه';
const kDemoNotVerified = 'پورتال دلفین این کارشناس را تأیید نکرد؛ دمو را نمی‌توان دید.';
const kDemoViewOnly = 'فقط تماشا';
const kDemoEnded = 'دمو تمام شد.';
const kDemoNotConnected = 'اتصال به رایانه‌ی کارشناس برقرار نشد. اگر هنوز می‌خواهید دمو را ببینید، به کارشناس بگویید دوباره امتحان کند.';

String demoAskTitle(String technician) => '$technician می‌خواهد صفحه‌ی خودش را به شما نشان دهد';

/// The demo window's title (D2).
String demoWindowTitle(String technician) => 'دمو از دلفین — $technician';

/// Seconds the customer has left to answer.
int demoSecondsLeft(DateTime seenAt, DateTime now) {
  final gone = now.difference(seenAt).inSeconds;
  if (gone < 0) return kDolphinDemoAskSecs;
  return gone >= kDolphinDemoAskSecs ? 0 : kDolphinDemoAskSecs - gone;
}

/// The customer's prompt, in place of the session view (D2). Only a technician the portal vouched for can be watched
/// ([canSee], the same rule as the accept prompt, D5); «نه» always works.
class DolphinDemoAskView extends StatelessWidget {
  final String technician;
  final bool canSee;
  final int secondsLeft;
  final String phone;
  final VoidCallback onSee;
  final VoidCallback onNo;
  const DolphinDemoAskView(
      {super.key,
      required this.technician,
      required this.canSee,
      required this.secondsLeft,
      required this.phone,
      required this.onSee,
      required this.onNo});

  @override
  Widget build(BuildContext context) => DolphinLight(child: Builder(builder: _build));

  Widget _build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.co_present_outlined, size: 36, color: DolphinColors.azure),
                const SizedBox(height: 10),
                Text(demoAskTitle(technician),
                    key: const ValueKey('dolphin-demo-ask-title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.7, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                const SizedBox(height: 8),
                Text(kDemoAskHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, height: 1.7, color: DolphinColors.muted)),
                if (!canSee) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: DolphinColors.amberSoft, borderRadius: BorderRadius.circular(DolphinRadii.field)),
                    child: Text('$kDemoNotVerified ${faDigits(phone)}',
                        style: TextStyle(fontSize: 12.5, height: 1.7, color: DolphinColors.amberText)),
                  ),
                ],
                const SizedBox(height: 10),
                Text('${faDigits('$secondsLeft')} ثانیه',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: DolphinColors.muted)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(children: [
              if (canSee) ...[
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('dolphin-demo-see'),
                    style: FilledButton.styleFrom(backgroundColor: DolphinColors.aquaText),
                    onPressed: onSee,
                    child: const Text(kDemoSee),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton(key: const ValueKey('dolphin-demo-no'), onPressed: onNo, child: const Text(kDemoNo)),
              ),
            ]),
          ),
        ]),
      );
}

/// The bottom strip of the customer's demo window (D2), in place of the session toolbar: whose screen, «فقط تماشا»,
/// the technician's screens when he allowed them all, «پایان دمو».
class DolphinDemoWindowBar extends StatelessWidget {
  final String title;
  final int screens;
  final int current;
  final ValueChanged<int>? onScreen;
  final VoidCallback onEnd;
  const DolphinDemoWindowBar(
      {super.key,
      required this.title,
      required this.onEnd,
      this.screens = 1,
      this.current = 0,
      this.onScreen});

  @override
  Widget build(BuildContext context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: DolphinColors.surface, border: Border(top: BorderSide(color: DolphinColors.line))),
            child: Row(children: [
              Flexible(
                child: Text(title,
                    key: const ValueKey('dolphin-demo-window-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, color: DolphinColors.ink, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: DolphinColors.azureSoft, borderRadius: BorderRadius.circular(99)),
                child: Text(kDemoViewOnly, style: TextStyle(fontSize: 11.5, color: DolphinColors.azureText)),
              ),
              if (screens > 1 && onScreen != null)
                for (var i = 0; i < screens; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: ChoiceChip(
                      key: ValueKey('dolphin-demo-screen-$i'),
                      selectedColor: DolphinColors.azureTint,
                      label: Text('صفحه‌ی ${faDigits('${i + 1}')}', style: const TextStyle(fontSize: 12)),
                      selected: i == current,
                      onSelected: (_) => onScreen!(i),
                    ),
                  ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('dolphin-demo-window-end'),
                style: FilledButton.styleFrom(
                    backgroundColor: DolphinColors.danger, minimumSize: const Size(64, 34)),
                onPressed: onEnd,
                child: const Text(kDemoEnd),
              ),
            ]),
          ),
        ),
      );
}

/// The customer's demo window after the end, or when it could not connect.
class DolphinDemoEndedView extends StatelessWidget {
  final bool wasConnected;
  final VoidCallback onClose;
  const DolphinDemoEndedView({super.key, required this.wasConnected, required this.onClose});

  @override
  Widget build(BuildContext context) => DolphinLight(
        paint: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(wasConnected ? Icons.check_circle_outline : Icons.info_outline,
                    color: wasConnected ? DolphinColors.aqua : DolphinColors.amberText),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(wasConnected ? kDemoEnded : kDemoNotConnected,
                        key: const ValueKey('dolphin-demo-ended-text'),
                        style: TextStyle(color: DolphinColors.ink, height: 1.6))),
              ]),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: OutlinedButton(onPressed: onClose, child: const Text(kDemoClose)),
              ),
            ]),
          ),
        ),
      );
}
