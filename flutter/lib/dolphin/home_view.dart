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

/// Under «درخواست‌ها و پیام‌ها» (UX-8) while signed out: the section needs a username from Dolphin.
const kRequestsWhoFor = 'با نام کاربری‌ای که دلفین به شما داده است؛ حساب ندارید؟ با پشتیبانی تماس بگیرید.';

/// What the stopped state says and its button.
const kServiceStoppedHint = 'تا سرویس روشن نشود کارشناس نمی‌تواند وصل شود؛ هر اتصال باز هم به اجازه‌ی شما نیاز دارد.';
/// DD-19: the button in the red notice (support_views.dart kFixLabel); upstream's start with its UAC prompt.
const kStartServiceLabel = kFixLabel;

/// Above the ID (design C1).
const kSayIdLine = 'این شناسه را پشت تلفن بگویید';

/// The footer's ⚙ (C5).
const kSettingsTooltip = 'تنظیمات';

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

/// The customer's main window (Plan 19 C1, 380 × 580, as approved on the design page): one big status card at the
/// top, the big readable ID with «کپی شناسه», three helper tiles, the network box, the «اشتراک‌گذاری» switch, and a
/// footer with the support phone, the version (About) and ⚙ (C5 settings). Everything older that the design does not
/// draw stays, under these in the same scroll: the one-time code (inside the ID card), the service-stopped,
/// no-monitor and ID-changed notices (under the status card), «با من تماس بگیرید», recent sessions, «درخواست‌ها و
/// پیام‌ها» and the DD-32 helpers. Pure: everything comes in as values.
class DolphinHomeView extends StatelessWidget {
  final String id;
  final DolphinServerState state;
  final VoidCallback onCopy;
  final String phone;

  /// The support site's name; shown small under the helpers.
  final String siteLabel;

  /// Opens «درخواست‌ها و پیام‌ها» (Plan 19 C4, native); hidden when null.
  final VoidCallback? onRequests;

  /// C4.6: requests with a new message from Dolphin (the red count on the row); 0 hides it.
  final int unread;

  /// UX-8's line under the row («با نام کاربری‌ای که دلفین به شما داده است…»): only while signed out.
  final bool requestsHint;

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
  /// the card says «کارشناس در راه است», while connected «… وصل است», with their photo.
  final TechComing? coming;

  /// Authorised sessions the server reports; null until the first read (no technician card before that).
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

  /// Plan 18 Phase 4: «بررسی سلامت» (DD-38), «گزارش» (DD-7), «عکس صفحه» (DD-48); a null callback hides its tile.
  final VoidCallback? onHealth;
  final VoidCallback? onReport;
  final VoidCallback? onScreenshot;

  /// DD-40: what to do on a PC with no monitor (health.dart headlessFix); '' hides the notice.
  final String headlessFix;

  /// DD-20: tapping the version opens About; null keeps it plain text.
  final VoidCallback? onAbout;

  /// DD-34, Plan 19 C1: the «اشتراک‌گذاری» switch (share.dart DolphinShareControl, which draws nothing when the portal
  /// hides it); null for none.
  final Widget? share;

  /// Plan 19 C5: ⚙ in the footer opens the customer's settings; null hides it.
  final VoidCallback? onSettings;

  const DolphinHomeView(
      {super.key,
      required this.id,
      required this.state,
      required this.onCopy,
      required this.phone,
      required this.siteLabel,
      this.onRequests,
      this.unread = 0,
      this.requestsHint = true,
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
      this.onAbout,
      this.share,
      this.onSettings});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: the customer's own look on any Windows theme

  BoxDecoration get _card => BoxDecoration(
        color: DolphinColors.surface,
        borderRadius: BorderRadius.circular(DolphinRadii.card),
        border: Border.all(color: DolphinColors.line),
      );

  Widget _idCard(bool down) {
    final onCopyCode = this.onCopyCode;
    return Container(
      key: const ValueKey('dolphin-id-card'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: _card,
      child: Column(children: [
        Text(kSayIdLine, textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
        const SizedBox(height: 6),
        // DD-44: Persian digits in groups of three. Not selectable: the copy button is the way to copy, and it gives
        // the Latin digits the technician's field takes.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(readableId(id),
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    height: 1.4,
                    color: down ? DolphinColors.muted : DolphinColors.ink)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('کپی شناسه'),
          ),
        ),
        if (code.isNotEmpty) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: DolphinColors.line),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('رمز یک‌بارمصرف', style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
            const SizedBox(width: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(code,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: DolphinColors.ink)),
            ),
            IconButton(
              tooltip: 'کپی رمز',
              icon: Icon(Icons.copy, size: 16, color: DolphinColors.muted),
              onPressed: onCopyCode,
            ),
          ]),
          Text(codeSpoken ? kCodeSpokenLine : kCodeForPortalLine,
              textAlign: TextAlign.center,
              style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
        ],
      ]),
    );
  }

  Widget _footer() {
    final onAbout = this.onAbout;
    final onSettings = this.onSettings;
    final small = TextStyle(color: DolphinColors.muted, fontSize: 12.5);
    return Container(
      key: const ValueKey('dolphin-home-footer'),
      decoration: BoxDecoration(color: DolphinColors.surface, border: Border(top: BorderSide(color: DolphinColors.line))),
      padding: EdgeInsetsDirectional.fromSTEB(14, 2, onSettings == null ? 14 : 4, 2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(children: [
          Icon(Icons.phone_outlined, size: 15, color: DolphinColors.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(phone.isEmpty ? 'پشتیبانی دلفین' : faDigits(phone),
                overflow: TextOverflow.ellipsis,
                semanticsLabel: phone.isEmpty ? null : 'پشتیبانی دلفین: ${faDigits(phone)}',
                style: small),
          ),
          // DD-32: our own version (TB-4), so the customer can read it to the technician; DD-20: it opens About.
          if (version.isNotEmpty)
            onAbout == null
                ? Text(versionLabel(version), style: small)
                : Tooltip(
                    message: 'درباره و به‌روزرسانی',
                    child: InkWell(
                      onTap: onAbout,
                      borderRadius: BorderRadius.circular(DolphinRadii.field),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(versionLabel(version),
                            style: TextStyle(
                                color: DolphinColors.azureText, fontSize: 12.5, decoration: TextDecoration.underline)),
                      ),
                    ),
                  ),
          if (onSettings != null)
            IconButton(
              key: const ValueKey('dolphin-settings'),
              tooltip: kSettingsTooltip,
              onPressed: onSettings,
              icon: Icon(Icons.settings_outlined, size: 20, color: DolphinColors.muted),
            ),
        ]),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final status = homeStatus(server: state, connected: connected, tech: coming);
    final down = state == DolphinServerState.offline || state == DolphinServerState.stopped;
    final onStartService = this.onStartService;
    final onRequests = this.onRequests;
    final onCallback = this.onCallback;
    final share = this.share;
    final helpers = DolphinHomeHelpers(
        onStartHere: onStartHere, onCopyIp: onCopyIp, onCopyDownload: onCopyDownload, onCopyGuide: onCopyGuide);
    final tools = DolphinSupportTools(onHealth: onHealth, onReport: onReport, onScreenshot: onScreenshot);
    const gap = SizedBox(height: 10);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: DolphinColors.ground,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  children: [
                    DolphinStatusBar(status: status),
                    if (state == DolphinServerState.stopped) ...[
                      gap,
                      DolphinServiceNotice(text: kServiceStoppedHint, onFix: onStartService),
                    ],
                    if (headlessFix.isNotEmpty) ...[
                      gap,
                      DolphinHeadlessNotice(fix: headlessFix),
                    ],
                    if (idChanged) ...[
                      gap,
                      DolphinIdNotice(onDismiss: onDismissIdNotice),
                    ],
                    gap,
                    _idCard(down),
                    if (!tools.isEmpty) ...[gap, tools],
                    if (onRequests != null) ...[
                      gap,
                      DolphinRequestsRow(onTap: onRequests, unread: unread),
                      // UX-8: most customers have no account; say so before they meet the sign-in.
                      if (requestsHint) ...[
                        const SizedBox(height: 6),
                        Text(
                          kRequestsWhoFor,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6),
                        ),
                      ],
                    ],
                    if (network.isNotEmpty) ...[gap, DolphinNetworkPanel(rows: network)],
                    if (share != null) ...[gap, share],
                    // As before: not while a technician is on the way, nor while the server is unreachable.
                    if (onCallback != null && status.bar != HomeBar.coming && !down) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: onCallback,
                          icon: const Icon(Icons.phone_callback_outlined, size: 18),
                          label: const Text(kCallbackLabel, style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DolphinColors.azureText,
                            backgroundColor: DolphinColors.surface,
                            side: BorderSide(color: DolphinColors.lineStrong),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control)),
                          ),
                        ),
                      ),
                    ],
                    if (recent.isNotEmpty) ...[
                      gap,
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        decoration: _card,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('آخرین اتصال‌ها به این رایانه',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: DolphinColors.ink)),
                            const SizedBox(height: 6),
                            for (final s in recent.take(3))
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(recentLine(s, DateTime.now()),
                                    style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (!helpers.isEmpty) ...[
                      const SizedBox(height: 14),
                      helpers,
                      if (siteLabel.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(siteLabel,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }
}
