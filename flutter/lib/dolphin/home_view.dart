import 'package:flutter/material.dart';

import 'callback.dart';
import 'digits.dart';
import 'home_status.dart';
import 'home_widgets.dart';
import 'network_status.dart';
import 'recent_sessions.dart';
import 'support_views.dart';
import 'tech_card.dart';
import 'theme.dart';

export 'home_status.dart' show DolphinServerState, serverStateFromStatus, kServiceStoppedLabel;

/// Under the one-time code in code mode: it goes into the portal, never over the phone.
const kCodeForPortalLine = 'رمز را فقط در «درخواست‌ها و پیام‌ها» یا پورتال ثبت کنید؛ پشت تلفن نخوانید.';

/// ADR-0012, click mode: the code may be read to the Dolphin technician instead of pressing «پذیرفتن».
const kCodeSpokenLine = 'این رمز را فقط به کارشناس دلفین بگویید؛ کارشناس با آن بدون «پذیرفتن» وصل می‌شود. رمز بعد از هر اتصال عوض می‌شود.';

/// Under «درخواست‌ها و پیام‌ها» (UX-8): the section is the customer portal, which needs a username from Dolphin.
const kRequestsWhoFor = 'با نام کاربری‌ای که دلفین به شما داده است؛ حساب ندارید؟ با پشتیبانی تماس بگیرید.';

/// What the stopped state says and its button.
const kServiceStoppedHint = 'تا سرویس روشن نشود کارشناس نمی‌تواند وصل شود؛ هر اتصال باز هم به اجازه‌ی شما نیاز دارد.';
/// DD-19: the button in the red notice (support_views.dart kFixLabel); upstream's start with its UAC prompt.
const kStartServiceLabel = kFixLabel;

/// Under the ID while the server is reachable (the offline bar says what to do instead).
const kWindowOpenLine = 'تا این پنجره باز است کسی بدون اجازه‌ی شما وصل نمی‌شود.';

/// The numbers the portal pushed, or the one compiled in until the first heartbeat brings them.
String supportPhone(String pushed, String compiled) => pushed.trim().isNotEmpty ? pushed.trim() : compiled;

/// "123456789" -> "123 456 789", so a customer can read it out on the phone.
String groupId(String id) {
  if (!RegExp(r'^\d+$').hasMatch(id)) return id;
  final out = StringBuffer();
  for (var i = 0; i < id.length; i++) {
    if (i > 0 && (id.length - i) % 3 == 0) out.write(' ');
    out.write(id[i]);
  }
  return out.toString();
}

/// DD-44: the ID as the customer reads it, «۱۲۳ ۴۵۶ ۷۸۹». The copy button puts Latin digits on the clipboard
/// (digits.dart idForClipboard).
String readableId(String id) => faDigits(groupId(id));

/// The customer's main window (design 2026-10-26, option B; portal look 2026-10-27; Plan 18 Phase 2). Pure: everything
/// comes in as values.
class DolphinHomeView extends StatelessWidget {
  final String id;
  final DolphinServerState state;
  final VoidCallback onCopy;
  final String phone;
  final String siteLabel;

  /// Opens the request section (the customer portal inside the app); hidden when null.
  final VoidCallback? onRequests;

  /// The one-time code (WF-3); '' hides it.
  final String code;

  /// ADR-0012: true in click mode, where the customer reads the code on the phone instead of typing it in the portal.
  final bool codeSpoken;
  final VoidCallback? onCopyCode;

  /// UN-15: the last finished sessions on this PC, newest first (pushed by the portal).
  final List<RecentSession> recent;

  /// Turns the service back on (Windows asks for admin rights); the button shows only in the stopped state.
  final VoidCallback? onStartService;

  /// Plan 14 (B5), DD-43: the technician the portal has authorized for this PC; null for none. Before they connect
  /// the bar says «کارشناس در راه است», while connected «کارشناس وصل است», with their photo and name.
  final TechComing? coming;

  /// Authorised sessions the server reports; null until the first read (no technician bar before that).
  final int? connected;

  /// Plan 14 (B6): opens «با من تماس بگیرید»; null hides the button (a PC not linked to an organization).
  final VoidCallback? onCallback;

  /// DD-8: the network box's two lines (network_status.dart networkRows: state and IP); empty hides the box.
  final List<NetRow> network;

  /// DD-32: «شناسه‌ی شما عوض شد», closed with [onDismissIdNotice].
  final bool idChanged;
  final VoidCallback? onDismissIdNotice;

  /// DD-32: the helper buttons; a null callback hides its button.
  final VoidCallback? onStartHere;
  final VoidCallback? onCopyIp;
  final VoidCallback? onCopyDownload;
  final VoidCallback? onCopyGuide;

  /// DD-32: Dolphin's own version at the bottom of the window; '' hides it.
  final String version;

  /// Plan 18 Phase 4: «بررسی سلامت» (DD-38), «گزارش برای پشتیبانی» (DD-7), «عکس صفحه برای پشتیبانی» (DD-48); a null
  /// callback hides its button.
  final VoidCallback? onHealth;
  final VoidCallback? onReport;
  final VoidCallback? onScreenshot;

  /// DD-40: what to do on a PC with no monitor (health.dart headlessFix); '' hides the notice.
  final String headlessFix;

  /// DD-20: tapping the version opens About («بررسی نسخه‌ی تازه»); null keeps it plain text.
  final VoidCallback? onAbout;

  const DolphinHomeView(
      {super.key,
      required this.id,
      required this.state,
      required this.onCopy,
      required this.phone,
      required this.siteLabel,
      this.onRequests,
      this.code = '',
      this.codeSpoken = false,
      this.onCopyCode,
      this.recent = const [],
      this.onStartService,
      this.coming,
      this.connected = 0,
      this.onCallback,
      this.network = const [],
      this.idChanged = false,
      this.onDismissIdNotice,
      this.onStartHere,
      this.onCopyIp,
      this.onCopyDownload,
      this.onCopyGuide,
      this.version = '',
      this.onHealth,
      this.onReport,
      this.onScreenshot,
      this.headlessFix = '',
      this.onAbout});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final status = homeStatus(server: state, connected: connected, tech: coming);
    final down = state == DolphinServerState.offline || state == DolphinServerState.stopped;
    final onStartService = this.onStartService;
    final onRequests = this.onRequests;
    final onCallback = this.onCallback;
    final helpers = DolphinHomeHelpers(
        onStartHere: onStartHere, onCopyIp: onCopyIp, onCopyDownload: onCopyDownload, onCopyGuide: onCopyGuide);
    final tools = DolphinSupportTools(onHealth: onHealth, onReport: onReport, onScreenshot: onScreenshot);
    final hint = switch (state) {
      DolphinServerState.stopped => '', // DD-19: the red notice under the bar says it, with «درست کن».
      DolphinServerState.offline => '', // DD-33: the offline bar already says what to do.
      _ => kWindowOpenLine,
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: DolphinColors.ground,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  children: [
                    DolphinStatusBar(status: status),
                    if (state == DolphinServerState.stopped) ...[
                      const SizedBox(height: 10),
                      DolphinServiceNotice(text: kServiceStoppedHint, onFix: onStartService),
                    ],
                    if (headlessFix.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DolphinHeadlessNotice(fix: headlessFix),
                    ],
                    if (idChanged) ...[
                      const SizedBox(height: 10),
                      DolphinIdNotice(onDismiss: onDismissIdNotice),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(DolphinRadii.card),
                        border: Border.all(color: DolphinColors.line),
                      ),
                      child: Column(
                        children: [
                          const Text('این شناسه را پشت تلفن به کارشناس دلفین بگویید',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                          const SizedBox(height: 10),
                          // DD-44: Persian digits in groups of three. Not selectable: the copy button is the way to
                          // copy, and it gives the Latin digits the technician's field takes.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(readableId(id),
                                  style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2,
                                      color: down ? DolphinColors.muted : DolphinColors.ink)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: onCopy,
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('کپی شناسه'),
                            ),
                          ),
                          if (code.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1, color: DolphinColors.line),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Text('رمز یک‌بارمصرف',
                                  style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                              const SizedBox(width: 8),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: SelectableText(code,
                                    style: const TextStyle(
                                        fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                              ),
                              IconButton(
                                tooltip: 'کپی رمز',
                                icon: const Icon(Icons.copy, size: 16, color: DolphinColors.muted),
                                onPressed: onCopyCode,
                              ),
                            ]),
                            Text(codeSpoken ? kCodeSpokenLine : kCodeForPortalLine,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
                          ],
                        ],
                      ),
                    ),
                    if (network.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DolphinNetworkPanel(rows: network),
                    ],
                    if (hint.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.7),
                      ),
                    ],
                    // As before: not while a technician is on the way, nor while the server is unreachable.
                    if (onCallback != null && status.bar != HomeBar.coming && !down) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: onCallback,
                          icon: const Icon(Icons.phone_callback_outlined, size: 18),
                          label: const Text(kCallbackLabel, style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DolphinColors.azure,
                            side: const BorderSide(color: DolphinColors.lineStrong),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control)),
                          ),
                        ),
                      ),
                    ],
                    if (recent.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(DolphinRadii.card),
                          border: Border.all(color: DolphinColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('آخرین اتصال‌ها به این رایانه',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                            const SizedBox(height: 6),
                            for (final s in recent.take(3))
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(recentLine(s, DateTime.now()),
                                    style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (onRequests != null) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: TextButton.icon(
                          onPressed: onRequests,
                          icon: const Icon(Icons.forum_outlined, size: 18),
                          label: const Text('درخواست‌ها و پیام‌ها',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: TextButton.styleFrom(
                            foregroundColor: DolphinColors.azure,
                            backgroundColor: DolphinColors.azureSoft,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(DolphinRadii.control)),
                          ),
                        ),
                      ),
                      // UX-8: most customers have no portal account; say so before they meet a sign-in page.
                      const SizedBox(height: 6),
                      const Text(
                        kRequestsWhoFor,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6),
                      ),
                    ],
                    if (!tools.isEmpty) ...[
                      const SizedBox(height: 14),
                      tools,
                    ],
                    if (!helpers.isEmpty) ...[
                      const SizedBox(height: 14),
                      helpers,
                    ],
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: DolphinColors.line))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                          phone.isEmpty ? 'پشتیبانی دلفین' : 'پشتیبانی دلفین: ${faDigits(phone)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                    ),
                    Text(siteLabel,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                  ],
                ),
                // DD-32: our own version (TB-4), so the customer can read it to the technician.
                if (version.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: onAbout == null
                        ? Text(versionLabel(version), style: const TextStyle(color: DolphinColors.muted, fontSize: 12))
                        : InkWell(
                            onTap: onAbout,
                            child: Text('${versionLabel(version)} · درباره و به‌روزرسانی',
                                style: const TextStyle(
                                    color: DolphinColors.azure, fontSize: 12, decoration: TextDecoration.underline)),
                          ),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
