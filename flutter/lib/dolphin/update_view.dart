import 'dart:convert';

import 'package:flutter/material.dart';

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

/// The screen shown instead of the app while it updates (TB-20). Pure: everything comes in as values.
class DolphinUpdateView extends StatelessWidget {
  final DolphinUpdateCheck check;
  final DolphinUpdateProgress progress;
  final VoidCallback onRetry;
  final VoidCallback onDownloadPage;
  final VoidCallback onClose;

  /// D19: after a failure the customer may open the app at its current version, for this run only.
  final VoidCallback? onContinue;

  const DolphinUpdateView(
      {super.key,
      required this.check,
      required this.progress,
      required this.onRetry,
      required this.onDownloadPage,
      required this.onClose,
      this.onContinue});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final error = progress.state == 'failed'
        ? progress.error
        : (check.state == 'blocked' && progress.state == 'idle' ? check.error : '');
    final children = <Widget>[
      const Text(kDolphinUpdateTitle,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
      const SizedBox(height: 8),
      Text(check.lead, style: const TextStyle(height: 1.8, color: DolphinColors.muted)),
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
          child: Text(error, style: const TextStyle(height: 1.8, color: DolphinColors.dangerText)),
        ),
        const SizedBox(height: 8),
        Text(check.phone, style: const TextStyle(height: 1.8, color: DolphinColors.ink)),
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
        Text(ready ? (progress.waiting ? kDolphinWaitingText : kDolphinApplyingText) : progress.text,
            style: const TextStyle(color: DolphinColors.muted)),
        // A lost link to the session count must never strand the customer: continue never cuts the session.
        if (progress.state == 'ready' && progress.waiting && onContinue != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onContinue, child: const Text('ادامه با همین نسخه')),
        ],
      ]);
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: DolphinColors.ground,
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}
