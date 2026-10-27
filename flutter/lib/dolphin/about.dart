import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/platform_model.dart';
import 'brand.dart';
import 'theme.dart';

/// The only place the upstream licence is mentioned. AGPL-3.0 needs the copyright notice and the source offer.
class DolphinAbout extends StatelessWidget {
  const DolphinAbout({super.key});

  @override
  Widget build(BuildContext context) {
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
            FutureBuilder<String>(
              future: bind.mainGetVersion(),
              builder: (context, snapshot) => Text('نسخه‌ی ${snapshot.data ?? ''}',
                  style: const TextStyle(color: DolphinColors.muted)),
            ),
            FutureBuilder<String>(
              future: bind.mainGetMyId(),
              builder: (context, snapshot) => SelectableText('شناسه‌ی این رایانه: ${snapshot.data ?? ''}',
                  style: const TextStyle(color: DolphinColors.muted)),
            ),
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
