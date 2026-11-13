import 'package:flutter/material.dart';

import 'updater.dart';
import 'widgets.dart';

/// Plan 19: the technician update's progress after «به‌روزرسانی»: downloading, waiting for open sessions, installing,
/// or why it failed with «تلاش دوباره» / «صفحه‌ی دانلود» / «بستن».
class TechUpdateProgressView extends StatelessWidget {
  final TechUpdater updater;
  final String version;
  final VoidCallback onRetry;
  final VoidCallback onDownloadPage;
  final VoidCallback onClose;
  const TechUpdateProgressView(
      {super.key,
      required this.updater,
      required this.version,
      required this.onRetry,
      required this.onDownloadPage,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: updater,
      builder: (context, _) {
        final failed = updater.phase == TechUpdatePhase.failed;
        return Container(
          key: const ValueKey('tech-update-progress'),
          width: 420,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: t.surface, border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radiusLarge)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('به‌روزرسانی برنامه‌ی کارشناس', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
            if (version.isNotEmpty) TechHint('نسخه‌ی ${version.replaceAllMapped(RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)])}'),
            const SizedBox(height: 14),
            if (!failed) ...[
              LinearProgressIndicator(color: t.primary, backgroundColor: t.surfaceAlt, minHeight: 6),
              const SizedBox(height: 10),
              Text(updater.text, style: TextStyle(color: t.text, height: 1.7)),
            ] else ...[
              TechNotice(updater.error),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                TechButton('تلاش دوباره', key: const ValueKey('update-retry'), kind: TechButtonKind.primary, onPressed: onRetry),
                TechButton('صفحه‌ی دانلود در پورتال', onPressed: onDownloadPage),
                TechButton('بستن', key: const ValueKey('update-close'), kind: TechButtonKind.quiet, onPressed: onClose),
              ]),
            ],
          ]),
        );
      },
    );
  }
}
