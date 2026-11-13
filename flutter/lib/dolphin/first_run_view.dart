import 'package:flutter/material.dart';

import 'home_view.dart';
import 'theme.dart';

/// Plan 19 C6 (DD-17 extended): the first-run guide, three steps with dots: the ID → how support works → permissions
/// and «پایان». «رد کردن» ends it at once; either way it is shown only once (home.dart remembers it locally).
const kFirstRunTitle = 'شناسه‌ی شما';
const kFirstRunIdHint = 'هر وقت به پشتیبانی نیاز داشتید، این شناسه را به کارشناس دلفین بگویید.';
const kFirstRunHowTitle = 'پشتیبانی چطور کار می‌کند';
const kFirstRunNext1 = 'این شناسه را پشت تلفن به کارشناس دلفین بگویید.';
const kFirstRunNext2 = 'کارشناس وصل می‌شود؛ هر وقت خواستید با «پایان» اتصال را قطع کنید.';
const kFirstRunHow3 = 'کارشناس فقط با اجازه‌ی پورتال دلفین و تا وقتی این پنجره باز است وصل می‌شود.';
const kFirstRunPermTitle = 'اجازه‌ها با شماست';
const kFirstRunPerm1 = 'ماوس و صفحه‌کلید، کلیپ‌بورد، انتقال فایل و صدای رایانه را در پنجره‌ی جلسه خودتان روشن و خاموش می‌کنید.';
const kFirstRunPerm2 = 'با «مکث» کارشناس تصویر را نمی‌بیند؛ مثلاً هنگام نوشتن رمز بانک.';
const kFirstRunPerm3 = 'اگر بخواهید، کادر رنگی دور صفحه نشان می‌دهد کسی وصل است (در «تنظیمات»).';
const kFirstRunSkipLabel = 'رد کردن';
const kFirstRunNextLabel = 'بعدی';
const kFirstRunDoneLabel = 'پایان';
const kFirstRunSteps = 3;

/// The step after [step] (0-based), or null when [step] was the last one: the guide ends.
int? firstRunNextStep(int step) => step + 1 < kFirstRunSteps ? step + 1 : null;

/// DD-17, Plan 19 C6. [onNext] ends the guide (after «پایان» or «رد کردن»). Pure apart from the step it is on.
class DolphinFirstRunView extends StatefulWidget {
  final String id;
  final VoidCallback onCopy;
  final VoidCallback onNext;

  /// The step to open on (previews and tests).
  final int initialStep;
  const DolphinFirstRunView(
      {super.key, required this.id, required this.onCopy, required this.onNext, this.initialStep = 0});

  @override
  State<DolphinFirstRunView> createState() => _DolphinFirstRunViewState();
}

class _DolphinFirstRunViewState extends State<DolphinFirstRunView> {
  late int _step = widget.initialStep.clamp(0, kFirstRunSteps - 1);

  @override
  Widget build(BuildContext context) => DolphinLight(child: Builder(builder: _build));

  void _next() {
    final next = firstRunNextStep(_step);
    if (next == null) {
      widget.onNext();
    } else {
      setState(() => _step = next);
    }
  }

  Widget _line(String n, String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: DolphinColors.azureSoft, shape: BoxShape.circle),
            child: Text(n, style: TextStyle(color: DolphinColors.azureText, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: DolphinColors.ink, fontSize: 13, height: 1.7))),
        ]),
      );

  Widget _title(String text) => Text(text,
      textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: DolphinColors.ink));

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Column(children: [
          _title(kFirstRunTitle),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DolphinColors.surface,
              borderRadius: BorderRadius.circular(DolphinRadii.card),
              border: Border.all(color: DolphinColors.line),
            ),
            child: Column(children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(widget.id.isEmpty ? '…' : readableId(widget.id),
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 2, color: DolphinColors.ink)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onCopy,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('کپی شناسه'),
                  style: OutlinedButton.styleFrom(foregroundColor: DolphinColors.azureText),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Text(kFirstRunIdHint,
              textAlign: TextAlign.center, style: TextStyle(color: DolphinColors.muted, fontSize: 13, height: 1.7)),
        ]);
      case 1:
        return Column(children: [
          _title(kFirstRunHowTitle),
          const SizedBox(height: 6),
          _line('۱', kFirstRunNext1),
          _line('۲', kFirstRunHow3),
          _line('۳', kFirstRunNext2),
        ]);
      default:
        return Column(children: [
          _title(kFirstRunPermTitle),
          const SizedBox(height: 6),
          _line('۱', kFirstRunPerm1),
          _line('۲', kFirstRunPerm2),
          _line('۳', kFirstRunPerm3),
        ]);
    }
  }

  Widget _build(BuildContext context) {
    final last = firstRunNextStep(_step) == null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: DolphinColors.ground,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(children: [
          Semantics(
            label: 'گام ${_step + 1} از $kFirstRunSteps',
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < kFirstRunSteps; i++)
                Container(
                  key: ValueKey('dolphin-firstrun-dot-$i'),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _step ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _step ? DolphinColors.azure : DolphinColors.fieldEdge,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(child: SingleChildScrollView(child: _stepBody())),
          const SizedBox(height: 12),
          Row(children: [
            if (!last) ...[
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('dolphin-firstrun-skip'),
                  onPressed: widget.onNext,
                  style: OutlinedButton.styleFrom(backgroundColor: DolphinColors.surface),
                  child: const Text(kFirstRunSkipLabel),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                key: const ValueKey('dolphin-firstrun-next'),
                onPressed: _next,
                child: Text(last ? kFirstRunDoneLabel : kFirstRunNextLabel),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
