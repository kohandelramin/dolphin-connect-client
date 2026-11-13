import 'package:flutter/material.dart';

import 'home_view.dart';
import 'theme.dart';

const kFirstRunTitle = 'شناسه‌ی شما این است، کپی کنید';
const kFirstRunNext1 = 'این شناسه را پشت تلفن به کارشناس دلفین بگویید.';
const kFirstRunNext2 = 'کارشناس وصل می‌شود؛ هر وقت خواستید با «پایان» اتصال را قطع کنید.';
const kFirstRunNextLabel = 'بعدی';

/// DD-17: shown once after install, before the home. «بعدی» goes on (home.dart remembers it locally). Pure view.
class DolphinFirstRunView extends StatelessWidget {
  final String id;
  final VoidCallback onCopy;
  final VoidCallback onNext;
  const DolphinFirstRunView({super.key, required this.id, required this.onCopy, required this.onNext});

  @override
  Widget build(BuildContext context) => DolphinLight(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    Widget step(String n, String text) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: DolphinColors.azureSoft, shape: BoxShape.circle),
            child: Text(n,
                style: const TextStyle(color: DolphinColors.azure, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: DolphinColors.ink, fontSize: 13, height: 1.7))),
        ]);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(color: DolphinColors.ground),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(children: [
                const Text(kFirstRunTitle,
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(DolphinRadii.card),
                    border: Border.all(color: DolphinColors.line),
                  ),
                  child: Column(children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(id.isEmpty ? '…' : readableId(id),
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 2, color: DolphinColors.ink)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('کپی شناسه'),
                        style: OutlinedButton.styleFrom(foregroundColor: DolphinColors.azure),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                step('۱', kFirstRunNext1),
                const SizedBox(height: 10),
                step('۲', kFirstRunNext2),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onNext, child: const Text(kFirstRunNextLabel)),
          ),
        ]),
      ),
    );
  }
}
