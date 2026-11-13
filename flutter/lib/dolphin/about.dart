import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/platform_model.dart';
import 'brand.dart';
import 'digits.dart';
import 'printer_hooks.dart';
import 'theme.dart';
import 'update.dart';

/// The only place the upstream licence is mentioned. AGPL-3.0 needs the copyright notice and the source offer.
class DolphinAbout extends StatelessWidget {
  const DolphinAbout({super.key});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build)); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    const link = TextStyle(color: DolphinColors.azure, decoration: TextDecoration.underline);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(DolphinBrand.nameFa,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(versionLabel(DolphinBrand.version), style: const TextStyle(color: DolphinColors.muted)),
            // DD-20: beside the start-up self-update (TB-20).
            const SizedBox(height: 8),
            const DolphinUpdateCheckButton(),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: bind.mainGetMyId(),
              builder: (context, snapshot) => SelectableText('شناسه‌ی این رایانه: ${snapshot.data ?? ''}',
                  style: const TextStyle(color: DolphinColors.muted)),
            ),
            // DD-41: the customer's virtual printer; nothing while the portal's `remote-printer` switch is hidden.
            if (bind.isIncomingOnly()) ...[const SizedBox(height: 10), const DolphinPrinterSection()],
            const SizedBox(height: 12),
            const Text('© ۱۴۰۵ دلفین · بخش‌هایی © Purslane Tech Pte. Ltd.'),
            Wrap(children: [
              const Text('مجوز AGPL-3.0 · '),
              InkWell(
                  onTap: () => launchUrl(Uri.parse(DolphinBrand.sourceUrl)),
                  child: const Text('کد منبع', style: link)),
              const Text(' · '),
              InkWell(
                  onTap: () => launchUrl(Uri.parse(DolphinBrand.site)),
                  child: const Text('حریم خصوصی', style: link)),
            ]),
          ],
        ),
      ),
    );
  }
}

/// DD-20: the customer window has no settings page, so its version line opens About in a dialog.
Future<void> showDolphinAboutDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const DolphinAbout(),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('بستن')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
