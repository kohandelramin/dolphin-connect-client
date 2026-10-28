import 'package:flutter/material.dart';

import 'digits.dart';
import 'theme.dart';

/// Under «درخواست‌ها و پیام‌ها» (UX-8): the section is the customer portal, which needs a username from Dolphin.
const kRequestsWhoFor = 'با نام کاربری‌ای که دلفین به شما داده است؛ حساب ندارید؟ با پشتیبانی تماس بگیرید.';

enum DolphinServerState { ready, connecting, offline }

/// The rendezvous status the client reports: 1 connected, 0 connecting, -1 not ready.
DolphinServerState serverStateFromStatus(int statusNum) => statusNum > 0
    ? DolphinServerState.ready
    : statusNum == 0
        ? DolphinServerState.connecting
        : DolphinServerState.offline;

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

/// The customer's main window (design 2026-10-26, option B; portal look 2026-10-27). Pure: everything comes in as values.
class DolphinHomeView extends StatelessWidget {
  final String id;
  final DolphinServerState state;
  final VoidCallback onCopy;
  final String phone;
  final String siteLabel;

  /// Opens the request section (the customer portal inside the app); hidden when null.
  final VoidCallback? onRequests;

  /// The one-time code in code mode (WF-3); '' hides it.
  final String code;
  final VoidCallback? onCopyCode;

  const DolphinHomeView(
      {super.key,
      required this.id,
      required this.state,
      required this.onCopy,
      required this.phone,
      required this.siteLabel,
      this.onRequests,
      this.code = '',
      this.onCopyCode});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    final (label, fg, bg) = switch (state) {
      DolphinServerState.ready => ('آماده؛ منتظر کارشناس', DolphinColors.aquaText, DolphinColors.aquaSoft),
      DolphinServerState.connecting => ('در حال اتصال به سرور دلفین…', DolphinColors.muted, DolphinColors.azureSoft),
      DolphinServerState.offline => ('به سرور دلفین وصل نیست', DolphinColors.dangerText, DolphinColors.dangerSoft),
    };
    final onRequests = this.onRequests;
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 8, height: 8, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]),
                    ),
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
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: SelectableText(groupId(id),
                                style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                    color: state == DolphinServerState.offline
                                        ? DolphinColors.muted
                                        : DolphinColors.ink)),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: onCopy,
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('کپی شناسه'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DolphinColors.azure,
                              side: const BorderSide(color: DolphinColors.lineStrong),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(DolphinRadii.control)),
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
                            const Text('رمز را فقط در «درخواست‌ها و پیام‌ها» یا پورتال ثبت کنید؛ پشت تلفن نخوانید.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state == DolphinServerState.offline
                          ? 'اینترنت را بررسی کنید؛ برنامه خودش دوباره تلاش می‌کند.'
                          : 'تا این پنجره باز است کسی بدون اجازه‌ی شما وصل نمی‌شود.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.7),
                    ),
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
                        phone.isEmpty ? 'پشتیبانی دلفین' : 'پشتیبانی دلفین: ${faDigits(phone)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                  ),
                  Text(siteLabel,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
