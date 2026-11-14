import 'package:flutter/material.dart';

import 'customer_ui/format.dart' show unreadBadge;
import 'home_helpers.dart';
import 'home_status.dart';
import 'network_status.dart';
import 'tech_card.dart';
import 'theme.dart';

/// DD-43, Plan 19 C1: one big status card at the top of the customer window: the status dot (DD-33), the title
/// («آماده برای پشتیبانی», «کارشناس در راه است», «… وصل است», «بدون اینترنت»), a second line and, while a technician
/// is on the way or connected, their photo. Centred, as the approved design. Pure: the status comes in as a value.
class DolphinStatusBar extends StatelessWidget {
  final HomeStatus status;
  const DolphinStatusBar({super.key, required this.status});

  static String title(HomeBar bar) => homeBarTitle(HomeStatus(bar));

  @override
  Widget build(BuildContext context) {
    final (fg, sub, bg) = switch (status.bar) {
      HomeBar.ready => (DolphinColors.aquaText, DolphinColors.muted, DolphinColors.aquaSoft),
      HomeBar.coming => (DolphinColors.azureText, DolphinColors.ink, DolphinColors.azureSoft),
      HomeBar.connected => (DolphinColors.onFill, DolphinColors.onFill, DolphinColors.azure),
      HomeBar.connecting => (DolphinColors.muted, DolphinColors.muted, DolphinColors.azureSoft),
      HomeBar.offline || HomeBar.stopped => (DolphinColors.dangerText, DolphinColors.dangerText, DolphinColors.dangerSoft),
    };
    // A quiet edge in the card's own hue (the filled card needs none).
    final edge = switch (status.bar) {
      HomeBar.ready => Color.lerp(DolphinColors.aquaSoft, DolphinColors.aqua, 0.3)!,
      HomeBar.connected => DolphinColors.azure,
      HomeBar.offline || HomeBar.stopped => Color.lerp(DolphinColors.dangerSoft, DolphinColors.danger, 0.3)!,
      _ => DolphinColors.line,
    };
    final detail = homeBarDetail(status);
    final withTech = status.bar == HomeBar.coming || status.bar == HomeBar.connected;
    // The portal's «در دسترس» dot: aqua while the server knows this PC, the field-edge grey otherwise.
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: status.online ? DolphinColors.aqua : DolphinColors.fieldEdge,
        shape: BoxShape.circle,
        border: status.bar == HomeBar.connected ? Border.all(color: DolphinColors.onFill, width: 1.5) : null,
      ),
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('dolphin-status-card'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(DolphinRadii.card), border: Border.all(color: edge)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (withTech) ...[
            DolphinTechAvatar(photo: status.tech?.photo, radius: 22),
            const SizedBox(height: 8),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            dot,
            const SizedBox(width: 8),
            Flexible(
              child: Text(homeBarTitle(status),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16.5)),
            ),
          ]),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 12.5, height: 1.6)),
          ],
          if (status.quietOffline) ...[
            const SizedBox(height: 3),
            Text(kBarOfflineQuiet, textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 12, height: 1.6)),
          ],
        ]),
      ),
    );
  }
}

/// DD-32: «شناسه‌ی شما عوض شد», until the customer closes it.
class DolphinIdNotice extends StatelessWidget {
  final VoidCallback? onDismiss;
  const DolphinIdNotice({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final onDismiss = this.onDismiss;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: DolphinColors.amberSoft,
        borderRadius: BorderRadius.circular(DolphinRadii.control),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 18, color: DolphinColors.amberText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(kIdChangedNotice,
              style: TextStyle(color: DolphinColors.amberText, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.6)),
        ),
        if (onDismiss != null)
          IconButton(
            tooltip: 'بستن',
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 16, color: DolphinColors.amberText),
          ),
      ]),
    );
  }
}

/// DD-8: the network box, two short lines a customer reads out on the phone (owner 2026-11-13): «وضعیت شبکه: متصل»
/// with a Wi-Fi icon that glows softly while connected, and «IP رایانه: …». Plan 19 C1: side by side in one box under
/// the helper tiles; on a narrow window the second goes under the first. No title above them: the first line already
/// says «وضعیت شبکه». The glow is still (no animation), so there is nothing to reduce for people who turn animations
/// off.
class DolphinNetworkPanel extends StatelessWidget {
  final List<NetRow> rows;
  const DolphinNetworkPanel({super.key, required this.rows});

  static Color colorOf(NetTone tone) => switch (tone) {
        NetTone.good => DolphinColors.aquaText,
        NetTone.neutral => DolphinColors.ink,
        NetTone.bad => DolphinColors.dangerText,
      };

  static const _iconBox = 26.0;

  static Widget _icon(NetRow r) {
    switch (r.kind) {
      case NetKind.status:
        if (r.tone == NetTone.good) {
          return Container(
            key: const ValueKey('dolphin-net-glow'),
            width: _iconBox,
            height: _iconBox,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DolphinColors.aquaSoft,
              boxShadow: [BoxShadow(color: DolphinColors.aqua.withOpacity(0.35), blurRadius: 10, spreadRadius: 1)],
            ),
            child: Icon(Icons.wifi, size: 16, color: DolphinColors.aqua),
          );
        }
        return SizedBox(
          width: _iconBox,
          height: _iconBox,
          child: Icon(Icons.wifi_off,
              size: 16, color: r.tone == NetTone.bad ? DolphinColors.dangerText : DolphinColors.muted),
        );
      case NetKind.address:
        return SizedBox(
            width: _iconBox, height: _iconBox, child: Icon(Icons.computer_outlined, size: 16, color: DolphinColors.muted));
      case NetKind.plain:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: DolphinColors.surface,
          borderRadius: BorderRadius.circular(DolphinRadii.control),
          border: Border.all(color: DolphinColors.line),
        ),
        // Each line keeps to the box's width (a long IPv6 address ends in «…» instead of spilling out).
        child: LayoutBuilder(
          builder: (context, box) => Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 2, spacing: 12, children: [
            for (final r in rows)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  KeyedSubtree(
                      key: r.kind == NetKind.status ? const ValueKey('dolphin-net-status-icon') : null, child: _icon(r)),
                  if (r.kind != NetKind.plain) const SizedBox(width: 6),
                  Text('${r.label}:', style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(r.value,
                        textDirection: r.ltr ? TextDirection.ltr : null,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colorOf(r.tone), fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
          ]),
        ),
      );
}

/// DD-32: «از اینجا شروع کنید» and the copy buttons. A null callback hides its button.
class DolphinHomeHelpers extends StatelessWidget {
  final VoidCallback? onStartHere;
  final VoidCallback? onCopyIp;
  final VoidCallback? onCopyDownload;
  final VoidCallback? onCopyGuide;
  const DolphinHomeHelpers({super.key, this.onStartHere, this.onCopyIp, this.onCopyDownload, this.onCopyGuide});

  bool get isEmpty => onStartHere == null && onCopyIp == null && onCopyDownload == null && onCopyGuide == null;

  @override
  Widget build(BuildContext context) {
    final onStartHere = this.onStartHere, onCopyIp = this.onCopyIp;
    final onCopyDownload = this.onCopyDownload, onCopyGuide = this.onCopyGuide;
    Widget copy(String label, VoidCallback onPressed) => OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.copy, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            foregroundColor: DolphinColors.azureText,
            backgroundColor: DolphinColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        );
    final copies = [
      if (onCopyIp != null) copy(kCopyMyIpLabel, onCopyIp),
      if (onCopyDownload != null) copy(kCopyDownloadLabel, onCopyDownload),
      if (onCopyGuide != null) copy(kCopyGuideLabel, onCopyGuide),
    ];
    return Column(children: [
      if (onStartHere != null)
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onStartHere,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text(kStartHereLabel),
            style: TextButton.styleFrom(
              foregroundColor: DolphinColors.azureText,
              backgroundColor: DolphinColors.azureSoft,
            ),
          ),
        ),
      if (copies.isNotEmpty) ...[
        if (onStartHere != null) const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: copies),
      ],
    ]);
  }
}

/// Plan 19 C4.6: «درخواست‌ها و پیام‌ها» as one row under the three tiles, with the red count of requests that have a
/// new message from Dolphin (asked every 30 s while signed in, customer_api/session.dart UnreadPoller).
class DolphinRequestsRow extends StatelessWidget {
  final VoidCallback onTap;
  final int unread;
  const DolphinRequestsRow({super.key, required this.onTap, this.unread = 0});

  static const label = 'درخواست‌ها و پیام‌ها';

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(DolphinRadii.control);
    return Semantics(
      button: true,
      label: unread > 0 ? '$label، ${unreadBadge(unread)} پیام تازه' : label,
      excludeSemantics: true,
      child: Material(
        key: const ValueKey('dolphin-requests-row'),
        color: DolphinColors.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: DolphinColors.line)),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
              child: Row(children: [
                Icon(Icons.forum_outlined, size: 18, color: DolphinColors.azureText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: DolphinColors.ink, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                if (unread > 0)
                  Container(
                    key: const ValueKey('dolphin-requests-unread'),
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: DolphinColors.danger, borderRadius: BorderRadius.circular(11)),
                    child: Text(unreadBadge(unread),
                        style: TextStyle(color: DolphinColors.onFill, fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.2)),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, size: 20, color: DolphinColors.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
