import 'dart:convert';

import 'package:flutter/material.dart';

import 'digits.dart';
import 'tech_theme.dart';
import 'theme.dart';

const kDolphinUpdateTitle = 'نسخه‌ی تازه‌ی دلفین کانکت';

/// One text for `ready` and `applying`, in this screen and in the Sciter one (src/dolphin_update_core.rs APPLYING_TEXT).
const kDolphinApplyingText = 'در حال نصب…';

/// Shown while a session keeps the install waiting (WAITING_TEXT): nothing on screen can cut the session.
const kDolphinWaitingText = 'پس از پایان جلسه نصب می‌شود.';

/// What the app learned before opening (src/dolphin_update.rs `check`). The texts arrive in Persian from Rust, so the
/// x64 and x86 screens say the same words.
class DolphinUpdateCheck {
  final String state; // current, update, manual or blocked
  final String version;
  final String lead;
  final String error;
  final String phone;
  final String downloadPage;

  const DolphinUpdateCheck(
      {required this.state, this.version = '', this.lead = '', this.error = '', this.phone = '', this.downloadPage = ''});

  static const current = DolphinUpdateCheck(state: 'current');

  /// Anything unreadable opens the app (owner decision D12).
  factory DolphinUpdateCheck.fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return current;
      final state = m['state'];
      if (state is! String || !const ['update', 'manual', 'blocked'].contains(state)) return current;
      String s(String key) => m[key] is String ? m[key] as String : '';
      return DolphinUpdateCheck(
          state: state,
          version: s('version'),
          lead: s('lead'),
          error: s('error'),
          phone: s('phone'),
          downloadPage: s('downloadPage'));
    } catch (_) {
      return current;
    }
  }

  /// The app stays closed while a newer version exists (owner decision D10).
  bool get blocksStart => state != 'current';
}

class DolphinUpdateProgress {
  final String state; // idle, downloading, ready, applying or failed
  final int percent;
  final String text;
  final String error;

  /// The download is done but a session is open, so the install waits for it to end (review I3).
  final bool waiting;

  const DolphinUpdateProgress(
      {required this.state, this.percent = 0, this.text = '', this.error = '', this.waiting = false});

  static const idle = DolphinUpdateProgress(state: 'idle');

  factory DolphinUpdateProgress.fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map<String, dynamic>) return idle;
      String s(String key) => m[key] is String ? m[key] as String : '';
      final percent = m['percent'] is int ? (m['percent'] as int).clamp(0, 100).toInt() : 0;
      final state = s('state');
      return DolphinUpdateProgress(
          state: state.isEmpty ? 'idle' : state,
          percent: percent,
          text: s('text'),
          error: s('error'),
          waiting: m['waiting'] == true);
    } catch (_) {
      return idle;
    }
  }
}

/// Plan 19: what the start-up check leads to. Every start asks the portal (TB-20's check); a newer build is
/// required in the customer app (D10: the app opens after the update) and offered in the technician app
/// («به‌روزرسانی» / «بعداً»: later keeps working with this version and asks again at the next start; nothing is stored).
enum StartUpdate { open, required, ask }

StartUpdate startUpdateAction(DolphinUpdateCheck check, {required bool technician}) {
  if (!check.blocksStart) return StartUpdate.open;
  return technician ? StartUpdate.ask : StartUpdate.required;
}

/// «نسخه‌ی شما: …» and «نسخه‌ی تازه: …» in the popups, Persian digits (our version, never RustDesk's 1.5.0).
String currentVersionLine(String version) => 'نسخه‌ی شما: ${faDigits(version)}';
String newVersionLine(String version) => 'نسخه‌ی تازه: ${faDigits(version)}';

/// «۴۸٪»
String percentText(int percent) => '${faDigits('$percent')}٪';

/// The update popup instead of the app while it updates (TB-20, D10; Plan 19: a clear popup with progress). Pure:
/// everything comes in as values. [framed] draws the popup card over the window's ground (the start-up window); the
/// in-app dialog (About, DD-20) is already a card.
class DolphinUpdateView extends StatelessWidget {
  final DolphinUpdateCheck check;
  final DolphinUpdateProgress progress;
  final VoidCallback onRetry;
  final VoidCallback onDownloadPage;
  final VoidCallback onClose;

  /// D19: after a failure the customer may open the app at its current version, for this run only.
  final VoidCallback? onContinue;

  /// This build's version (DolphinBrand.version); '' leaves the line out.
  final String currentVersion;
  final bool framed;

  const DolphinUpdateView(
      {super.key,
      required this.check,
      required this.progress,
      required this.onRetry,
      required this.onDownloadPage,
      required this.onClose,
      this.onContinue,
      this.currentVersion = '',
      this.framed = true});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final error = progress.state == 'failed'
        ? progress.error
        : (check.state == 'blocked' && progress.state == 'idle' ? check.error : '');
    final children = <Widget>[
      DolphinUpdateHeader(
          title: kDolphinUpdateTitle,
          current: currentVersion,
          next: check.version,
          ink: DolphinColors.ink,
          muted: DolphinColors.muted,
          accent: DolphinColors.azureText,
          soft: DolphinColors.azureSoft),
      const SizedBox(height: 12),
      Text(check.lead, style: TextStyle(height: 1.8, color: DolphinColors.muted)),
      const SizedBox(height: 16),
    ];
    if (check.state == 'manual') {
      children.add(Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(onPressed: onDownloadPage, child: const Text('دریافت دستی')),
        TextButton(onPressed: onClose, child: const Text('بستن')),
      ]));
    } else if (error.isNotEmpty) {
      children.addAll([
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: DolphinColors.dangerSoft, borderRadius: BorderRadius.circular(DolphinRadii.control)),
          child: Text(error, style: TextStyle(height: 1.8, color: DolphinColors.dangerText)),
        ),
        const SizedBox(height: 8),
        Text(check.phone, style: TextStyle(height: 1.8, color: DolphinColors.ink)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
          if (onContinue != null) OutlinedButton(onPressed: onContinue, child: const Text('ادامه با همین نسخه')),
          OutlinedButton(onPressed: onDownloadPage, child: const Text('دریافت دستی')),
          TextButton(onPressed: onClose, child: const Text('بستن')),
        ]),
      ]);
    } else {
      // `applying` is the swap in progress: the same bar and message as `ready`, never a failure.
      final ready = progress.state == 'ready' || progress.state == 'applying';
      children.addAll([
        LinearProgressIndicator(
          value: ready ? 1 : progress.percent / 100,
          minHeight: 10,
          borderRadius: BorderRadius.circular(5),
          color: DolphinColors.azure,
          backgroundColor: DolphinColors.azureSoft,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(ready ? (progress.waiting ? kDolphinWaitingText : kDolphinApplyingText) : progress.text,
                style: TextStyle(color: DolphinColors.muted)),
          ),
          if (!ready && progress.state == 'downloading')
            Text(percentText(progress.percent), style: TextStyle(color: DolphinColors.ink, fontWeight: FontWeight.w700)),
        ]),
        // A lost link to the session count must never strand the customer: continue never cuts the session.
        if (progress.state == 'ready' && progress.waiting && onContinue != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onContinue, child: const Text('ادامه با همین نسخه')),
        ],
      ]);
    }
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: framed
          ? Container(
              color: DolphinColors.ground,
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: SingleChildScrollView(child: DolphinPopupCard(child: body)),
            )
          : Container(color: DolphinColors.surface, padding: const EdgeInsets.all(24), child: body),
    );
  }
}

/// The popup's card: the surface colour, the large radius, a hairline and a soft shadow (the tokens in use).
class DolphinPopupCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? border;
  const DolphinPopupCard({super.key, required this.child, this.color, this.border});

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color ?? DolphinColors.surface,
          borderRadius: BorderRadius.circular(DolphinRadii.card),
          border: Border.all(color: border ?? DolphinColors.line),
          boxShadow: [BoxShadow(color: DolphinColors.ink.withOpacity(0.10), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

/// The icon, the title and the two version lines at the top of both popups.
class DolphinUpdateHeader extends StatelessWidget {
  final String title;
  final String current;
  final String next;
  final Color ink, muted, accent, soft;
  const DolphinUpdateHeader(
      {super.key,
      required this.title,
      required this.current,
      required this.next,
      required this.ink,
      required this.muted,
      required this.accent,
      required this.soft});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
          child: Icon(Icons.system_update_alt, color: accent, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 2),
            if (next.isNotEmpty)
              Text(newVersionLine(next), style: TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600)),
            if (current.isNotEmpty) Text(currentVersionLine(current), style: TextStyle(fontSize: 12.5, color: muted)),
          ]),
        ),
      ]);
}

const kTechUpdateTitle = 'نسخه‌ی تازه‌ی برنامه‌ی کارشناس';
const kTechUpdateNow = 'به‌روزرسانی';
const kTechUpdateLater = 'بعداً';
const kTechUpdateLaterHint = 'با «بعداً» با همین نسخه کار می‌کنید؛ دفعه‌ی بعد که برنامه باز شود دوباره می‌پرسیم.';

/// Plan 19: the technician app's popup at start. The app is already open behind it; «بعداً» closes the popup and
/// work goes on with this version. Light or dark with the technician's choice (DD-53). Pure.
class DolphinTechUpdatePopupView extends StatelessWidget {
  final DolphinUpdateCheck check;
  final String currentVersion;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  const DolphinTechUpdatePopupView(
      {super.key, required this.check, required this.onUpdate, required this.onLater, this.currentVersion = ''});

  @override
  Widget build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DolphinPopupCard(
        color: p.surface,
        border: p.line,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          DolphinUpdateHeader(
              title: kTechUpdateTitle,
              current: currentVersion,
              next: check.version,
              ink: p.ink,
              muted: p.muted,
              accent: p.accent,
              soft: p.accentSoft),
          const SizedBox(height: 12),
          if (check.lead.isNotEmpty) Text(check.lead, style: TextStyle(height: 1.8, color: p.ink)),
          const SizedBox(height: 6),
          Text(kTechUpdateLaterHint, style: TextStyle(height: 1.7, fontSize: 12.5, color: p.muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: onUpdate, icon: const Icon(Icons.download, size: 18), label: const Text(kTechUpdateNow)),
            TextButton(
                onPressed: onLater,
                style: TextButton.styleFrom(foregroundColor: p.accent),
                child: const Text(kTechUpdateLater)),
          ]),
        ]),
      ),
    );
  }
}
