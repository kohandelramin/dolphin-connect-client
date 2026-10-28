import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import 'call_status.dart';
import 'home_view.dart';
import 'theme.dart';

/// The technician window's top row: brand, own ID, and the manual connect field. Colours are explicit and the row sits
/// in [DolphinLight], so a dark Windows cannot turn the ID white on white (AUI-2).
class DolphinTechnicianHeader extends StatelessWidget {
  final String myId;
  final TextEditingController manual;
  final DolphinCallWait call;
  final VoidCallback onConnect;

  const DolphinTechnicianHeader(
      {super.key, required this.myId, required this.manual, required this.call, required this.onConnect});

  @override
  Widget build(BuildContext context) => DolphinLight(child: Builder(builder: _build), paint: false);

  Widget _build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(DolphinRadii.field),
        borderSide: const BorderSide(color: DolphinColors.lineStrong));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white, border: Border(bottom: BorderSide(color: DolphinColors.line))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Text('دلفین کانکت',
                style: TextStyle(fontWeight: FontWeight.w800, color: DolphinColors.azure)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: DolphinColors.azureSoft, borderRadius: BorderRadius.circular(99)),
              child: const Text('کارشناس',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: DolphinColors.azure)),
            ),
            const SizedBox(width: 16),
            const Text('شناسه‌ی شما', style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
            const SizedBox(width: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(myId.isEmpty ? '…' : groupId(myId),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: DolphinColors.ink)),
            ),
            IconButton(
              tooltip: 'کپی شناسه',
              icon: const Icon(Icons.copy, size: 16, color: DolphinColors.muted),
              onPressed: myId.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: myId));
                      showToast('کپی شد');
                    },
            ),
            const Spacer(),
            SizedBox(
              width: 180,
              child: TextField(
                controller: manual,
                enabled: !call.busy,
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: DolphinColors.ink),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'شناسه‌ی مشتری',
                  hintStyle: const TextStyle(color: DolphinColors.muted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                ),
                onSubmitted: (_) => onConnect(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: DolphinColors.azure,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control))),
              onPressed: call.busy ? null : onConnect,
              child: const Text('اتصال'),
            ),
          ],
        ),
      ),
    );
  }
}
