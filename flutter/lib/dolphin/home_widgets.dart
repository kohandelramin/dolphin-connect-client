import 'package:flutter/material.dart';

import 'home_helpers.dart';
import 'home_status.dart';
import 'network_status.dart';
import 'tech_card.dart';
import 'theme.dart';

/// DD-43: one large coloured bar at the top of the customer window, with the status dot (DD-33) and, while a
/// technician is on the way or connected, their photo and name. Pure: the status comes in as a value.
class DolphinStatusBar extends StatelessWidget {
  final HomeStatus status;
  const DolphinStatusBar({super.key, required this.status});

  static String title(HomeBar bar) => switch (bar) {
        HomeBar.ready => kBarReady,
        HomeBar.coming => kBarComing,
        HomeBar.connected => kBarConnected,
        HomeBar.connecting => kBarConnecting,
        HomeBar.offline => kBarOffline,
        HomeBar.stopped => kServiceStoppedLabel,
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (status.bar) {
      HomeBar.ready => (DolphinColors.aquaText, DolphinColors.aquaSoft),
      HomeBar.coming => (DolphinColors.azure, DolphinColors.azureSoft),
      HomeBar.connected => (Colors.white, DolphinColors.azure),
      HomeBar.connecting => (DolphinColors.muted, DolphinColors.azureSoft),
      HomeBar.offline || HomeBar.stopped => (DolphinColors.dangerText, DolphinColors.dangerSoft),
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
        border: status.bar == HomeBar.connected ? Border.all(color: Colors.white, width: 1.5) : null,
      ),
    );
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(DolphinRadii.card)),
        child: Row(children: [
          if (withTech) ...[
            DolphinTechAvatar(photo: status.tech?.photo, radius: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                dot,
                const SizedBox(width: 8),
                Flexible(
                  child: Text(title(status.bar),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15.5)),
                ),
              ]),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(detail, style: TextStyle(color: fg, fontSize: 12.5, height: 1.6)),
              ],
              if (status.quietOffline) ...[
                const SizedBox(height: 3),
                Text(kBarOfflineQuiet, style: TextStyle(color: fg, fontSize: 12, height: 1.6)),
              ],
            ]),
          ),
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
        const Icon(Icons.info_outline, size: 18, color: DolphinColors.amberText),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(kIdChangedNotice,
              style: TextStyle(color: DolphinColors.amberText, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.6)),
        ),
        if (onDismiss != null)
          IconButton(
            tooltip: 'بستن',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16, color: DolphinColors.amberText),
          ),
      ]),
    );
  }
}

/// DD-8: the network box under the ID, two short lines a customer reads out on the phone (owner 2026-11-13):
/// «وضعیت شبکه: متصل» with a Wi-Fi icon that glows softly while connected, and «IP رایانه: …». No title above them:
/// the first line already says «وضعیت شبکه». The glow is still (no animation), so there is nothing to reduce for
/// people who turn animations off.
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
            child: const Icon(Icons.wifi, size: 16, color: DolphinColors.aqua),
          );
        }
        return SizedBox(
          width: _iconBox,
          height: _iconBox,
          child: Icon(Icons.wifi_off,
              size: 16, color: r.tone == NetTone.bad ? DolphinColors.dangerText : DolphinColors.muted),
        );
      case NetKind.address:
        return const SizedBox(
            width: _iconBox, height: _iconBox, child: Icon(Icons.computer_outlined, size: 16, color: DolphinColors.muted));
      case NetKind.plain:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DolphinRadii.card),
          border: Border.all(color: DolphinColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, r) in rows.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Row(children: [
                KeyedSubtree(
                    key: r.kind == NetKind.status ? const ValueKey('dolphin-net-status-icon') : null, child: _icon(r)),
                if (r.kind != NetKind.plain) const SizedBox(width: 10),
                Text('${r.label}:', style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(r.value,
                      textDirection: r.ltr ? TextDirection.ltr : null,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorOf(r.tone), fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
        ]),
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
            foregroundColor: DolphinColors.azure,
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
              foregroundColor: DolphinColors.azure,
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
