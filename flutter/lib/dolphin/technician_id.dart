import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'home_view.dart';
import 'theme.dart';

/// The technician build is outgoing-only, so upstream hides its ID. The portal needs that ID to recognise the
/// technician's connections (staff profile «حساب من»), so we show it with a copy button.
class DolphinTechnicianId extends StatelessWidget {
  const DolphinTechnicianId({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: bind.mainGetMyId(),
      builder: (context, snapshot) => DolphinTechnicianIdView(
        id: snapshot.data ?? '',
        onCopy: () {
          Clipboard.setData(ClipboardData(text: snapshot.data ?? ''));
          showToast('کپی شد');
        },
      ),
    );
  }
}

/// Pure view, widget-tested.
class DolphinTechnicianIdView extends StatelessWidget {
  final String id;
  final VoidCallback onCopy;
  const DolphinTechnicianIdView({super.key, required this.id, required this.onCopy});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build), paint: false); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: DolphinColors.line),
            borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('شناسه‌ی کارشناسیِ شما',
                style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
            Row(children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(id.isEmpty ? '…' : groupId(id),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: DolphinColors.ink)),
                ),
              ),
              TextButton(onPressed: id.isEmpty ? null : onCopy, child: const Text('کپی')),
            ]),
            const Text('این شناسه را در «حساب من» در پورتال ثبت کنید؛ سرور فقط اتصال از همین شناسه را می‌پذیرد.',
                style: TextStyle(color: DolphinColors.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
