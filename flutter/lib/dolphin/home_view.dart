import 'package:flutter/material.dart';

import 'theme.dart';

enum DolphinServerState { ready, connecting, offline }

/// The rendezvous status the client reports: 1 connected, 0 connecting, -1 not ready.
DolphinServerState serverStateFromStatus(int statusNum) => statusNum > 0
    ? DolphinServerState.ready
    : statusNum == 0
        ? DolphinServerState.connecting
        : DolphinServerState.offline;

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

/// The customer's main window (design 2026-10-26, option B). Pure: everything comes in as values.
class DolphinHomeView extends StatelessWidget {
  final String id;
  final DolphinServerState state;
  final VoidCallback onCopy;
  final String phone;
  final String siteLabel;

  const DolphinHomeView(
      {super.key,
      required this.id,
      required this.state,
      required this.onCopy,
      required this.phone,
      required this.siteLabel});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (state) {
      DolphinServerState.ready => (
          'آماده؛ منتظر کارشناس',
          const Color(0xFF0F766E),
          const Color(0xFFCCFBF1)
        ),
      DolphinServerState.connecting => (
          'در حال اتصال به سرور دلفین…',
          DolphinColors.muted,
          const Color(0xFFEEF2F8)
        ),
      DolphinServerState.offline => (
          'به سرور دلفین وصل نیست',
          const Color(0xFFB91C1C),
          const Color(0xFFFEE2E2)
        ),
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: DolphinColors.ground,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Column(
                  children: [
                    const Text('این شناسه را پشت تلفن به کارشناس دلفین بگویید',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: DolphinColors.muted, fontSize: 13)),
                    const SizedBox(height: 10),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(groupId(id),
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: state == DolphinServerState.offline
                                  ? DolphinColors.muted
                                  : DolphinColors.ink)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: onCopy,
                      style: OutlinedButton.styleFrom(
                          foregroundColor: DolphinColors.azure,
                          side: const BorderSide(color: DolphinColors.azure)),
                      child: const Text('کپی شناسه'),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(99)),
                      child: Text('● $label',
                          style: TextStyle(
                              color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state == DolphinServerState.offline
                          ? 'اینترنت را بررسی کنید؛ برنامه خودش دوباره تلاش می‌کند.'
                          : 'تا این پنجره باز است کسی بدون اجازه‌ی شما وصل نمی‌شود.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DolphinColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: DolphinColors.line))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                        phone.isEmpty ? 'پشتیبانی دلفین' : 'پشتیبانی دلفین · $phone',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: DolphinColors.muted, fontSize: 11.5)),
                  ),
                  Text(siteLabel,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: DolphinColors.muted, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
