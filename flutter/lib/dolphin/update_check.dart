import 'dart:convert';

import 'package:flutter/material.dart';

import 'digits.dart';
import 'theme.dart';
import 'update_view.dart';

/// DD-20: «بررسی نسخه‌ی تازه» in About, beside the start-up self-update (TB-20). It asks the portal the same question
/// (`dolphin-update-recheck`, src/dolphin_update.rs `recheck`) and, when a newer build exists, starts the same update
/// screen (update.dart DolphinUpdateScreen) in a dialog.
const kCheckUpdateLabel = 'بررسی نسخه‌ی تازه';
const kCheckingText = 'در حال بررسی…';
const kUpToDateText = 'نسخه‌ی شما تازه است';
const kUpdateLabel = 'به‌روزرسانی';
const kCheckUnreachableText = 'پورتال دلفین پاسخ نداد؛ اینترنت را بررسی کنید و دوباره امتحان کنید.';
const kCheckDisabledText = 'این نسخه‌ی آزمایشی است و از پورتال به‌روز نمی‌شود.';
const kCheckAgainLabel = 'دوباره بررسی کن';

String foundText(String version) => 'نسخه‌ی ${faDigits(version)} آماده است.';

/// In the dialog the app is already open, so the start-up lead («پیش از باز شدن برنامه…») does not fit.
String inAppLead(String version) =>
    'نسخه‌ی ${faDigits(version)} از پورتال دلفین دریافت، بررسی و نصب می‌شود و برنامه دوباره باز می‌شود. '
    'اگر کارشناس وصل است، نصب تا پایان جلسه صبر می‌کند.';

enum UpdateCheckPhase { idle, checking, latest, found, unreachable, disabled }

class ManualUpdateCheck {
  final UpdateCheckPhase phase;

  /// What the update screen gets when the phase is [UpdateCheckPhase.found] (update, manual or blocked).
  final DolphinUpdateCheck screen;

  const ManualUpdateCheck(this.phase, [this.screen = DolphinUpdateCheck.current]);

  String get version => screen.version;

  /// Never says «تازه است» without the portal's word: anything unreadable or without a reason is "unreachable".
  factory ManualUpdateCheck.fromJson(String raw) {
    final screen = DolphinUpdateCheck.fromJson(raw);
    if (screen.blocksStart) {
      return ManualUpdateCheck(UpdateCheckPhase.found, inAppCheck(screen));
    }
    try {
      final m = jsonDecode(raw);
      final reason = m is Map ? m['reason'] : null;
      if (reason == 'latest') return const ManualUpdateCheck(UpdateCheckPhase.latest);
      if (reason == 'disabled') return const ManualUpdateCheck(UpdateCheckPhase.disabled);
    } catch (_) {}
    return const ManualUpdateCheck(UpdateCheckPhase.unreachable);
  }
}

/// The start-up answer with the in-app lead; the technician's manual text (D13) stays as Rust wrote it.
DolphinUpdateCheck inAppCheck(DolphinUpdateCheck c) => c.state == 'manual'
    ? c
    : DolphinUpdateCheck(
        state: c.state, version: c.version, lead: inAppLead(c.version), error: c.error, phone: c.phone, downloadPage: c.downloadPage);

/// The About section's row. Pure: everything comes in as values.
class DolphinUpdateCheckView extends StatelessWidget {
  final UpdateCheckPhase phase;
  final String version;
  final VoidCallback onCheck;
  final VoidCallback onUpdate;

  const DolphinUpdateCheckView(
      {super.key, required this.phase, this.version = '', required this.onCheck, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final checking = phase == UpdateCheckPhase.checking;
    final Widget? status = switch (phase) {
      UpdateCheckPhase.idle => null,
      UpdateCheckPhase.checking => const _Line(
          icon: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), text: kCheckingText),
      UpdateCheckPhase.latest => const _Line(
          icon: Icon(Icons.check_circle, size: 18, color: DolphinColors.aqua), text: kUpToDateText, color: DolphinColors.aquaText),
      UpdateCheckPhase.found => _Line(
          icon: const Icon(Icons.system_update_alt, size: 18, color: DolphinColors.azure),
          text: foundText(version),
          color: DolphinColors.ink,
          bold: true),
      UpdateCheckPhase.unreachable => const _Line(
          icon: Icon(Icons.cloud_off, size: 18, color: DolphinColors.amberText),
          text: kCheckUnreachableText,
          color: DolphinColors.amberText),
      UpdateCheckPhase.disabled =>
        const _Line(icon: Icon(Icons.science_outlined, size: 18, color: DolphinColors.muted), text: kCheckDisabledText),
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (phase == UpdateCheckPhase.found)
              FilledButton.icon(
                  onPressed: onUpdate,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text(kUpdateLabel, style: TextStyle(fontWeight: FontWeight.w700))),
            OutlinedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(phase == UpdateCheckPhase.idle || checking ? kCheckUpdateLabel : kCheckAgainLabel),
            ),
          ]),
          if (status != null) ...[const SizedBox(height: 8), status],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final Widget icon;
  final String text;
  final Color color;
  final bool bold;
  const _Line({required this.icon, required this.text, this.color = DolphinColors.muted, this.bold = false});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: icon),
        const SizedBox(width: 8),
        Flexible(
            child: Text(text,
                style: TextStyle(color: color, height: 1.7, fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
      ]);
}
