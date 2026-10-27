import 'package:flutter/material.dart';

import 'home_view.dart';
import 'panel_bridge.dart';
import 'portal_view.dart';
import 'theme.dart';

/// The customer build's request section: the customer portal inside the app. The customer signs in
/// with their portal username and password; the page gets this PC's ID from the app and nothing else.
class DolphinCustomerRequests extends StatelessWidget {
  final String id;
  final VoidCallback onBack;

  const DolphinCustomerRequests({super.key, required this.id, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
                color: Colors.white, border: Border(bottom: BorderSide(color: DolphinColors.line))),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('بازگشت'),
                  style: TextButton.styleFrom(foregroundColor: DolphinColors.muted),
                ),
                const SizedBox(width: 6),
                const Text('درخواست‌ها و پیام‌ها',
                    style: TextStyle(fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                const Spacer(),
                if (id.isNotEmpty) ...[
                  const Text('شناسه‌ی این رایانه', style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
                  const SizedBox(width: 6),
                  Text(groupId(id),
                      textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          Expanded(
            child: DolphinPortalView(path: '/portal', onMessage: (m) async => customerReply(m, id)),
          ),
        ],
      ),
    );
  }
}
