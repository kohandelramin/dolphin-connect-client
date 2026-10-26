import 'package:flutter/material.dart';

import 'theme.dart';

typedef DolphinAccept = void Function(bool keyboard, bool clipboard, bool file);

/// The prompt a customer answers before a technician gets in. File transfer starts off.
class DolphinAcceptView extends StatefulWidget {
  final String technician;
  final DolphinAccept onAccept;
  final VoidCallback onDeny;
  final bool showElevate;
  final DolphinAccept? onAcceptElevate;

  const DolphinAcceptView(
      {super.key,
      required this.technician,
      required this.onAccept,
      required this.onDeny,
      this.showElevate = false,
      this.onAcceptElevate});

  @override
  State<DolphinAcceptView> createState() => _DolphinAcceptViewState();
}

class _DolphinAcceptViewState extends State<DolphinAcceptView> {
  bool keyboard = true;
  bool clipboard = true;
  bool file = false;

  Widget _toggle(String label, bool value, ValueChanged<bool> set) => FilterChip(
        label: Text(label),
        selected: value,
        onSelected: (v) => setState(() => set(v)),
        selectedColor: const Color(0xFFDBE7FB),
        checkmarkColor: DolphinColors.azure,
      );

  @override
  Widget build(BuildContext context) {
    final onAcceptElevate = widget.onAcceptElevate;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const CircleAvatar(
                radius: 22,
                backgroundColor: DolphinColors.azure,
                child: Icon(Icons.support_agent, color: Colors.white)),
            const SizedBox(height: 10),
            Text('${widget.technician} از دلفین',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Text('می‌خواهد به این رایانه وصل شود',
                style: TextStyle(color: DolphinColors.muted)),
            const SizedBox(height: 12),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  _toggle('موس و صفحه‌کلید', keyboard, (v) => keyboard = v),
                  _toggle('کلیپ‌بورد', clipboard, (v) => clipboard = v),
                  _toggle('انتقال فایل', file, (v) => file = v),
                ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: DolphinColors.azure),
                  onPressed: () => widget.onAccept(keyboard, clipboard, file),
                  child: const Text('پذیرفتن'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: widget.onDeny, child: const Text('رد'))),
            ]),
            if (widget.showElevate && onAcceptElevate != null)
              TextButton(
                onPressed: () => onAcceptElevate(keyboard, clipboard, file),
                child: const Text('پذیرفتن با اجازه‌ی مدیر ویندوز'),
              ),
            const SizedBox(height: 8),
            const Text('اگر این نام را نمی‌شناسید «رد» را بزنید.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DolphinColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

String _mmss(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// While a technician is connected: who, for how long, file transfer, and the End button.
class DolphinSessionView extends StatelessWidget {
  final String technician;
  final Duration elapsed;
  final bool fileEnabled;
  final ValueChanged<bool> onFile;
  final VoidCallback onEnd;

  const DolphinSessionView(
      {super.key,
      required this.technician,
      required this.elapsed,
      required this.fileEnabled,
      required this.onFile,
      required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(99)),
              child: const Text('● در جلسه',
                  style: TextStyle(
                      color: DolphinColors.azure, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            Text(technician,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(_mmss(elapsed),
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: DolphinColors.muted)),
            const SizedBox(height: 10),
            FilterChip(
                label: const Text('انتقال فایل'),
                selected: fileEnabled,
                onSelected: onFile),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: DolphinColors.danger),
                onPressed: onEnd,
                child: const Text('پایان'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// After a session ends, until the customer closes the window.
class DolphinEndedView extends StatelessWidget {
  final VoidCallback onClose;
  const DolphinEndedView({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('جلسه پایان یافت.',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onClose, child: const Text('بستن')),
          ]),
        ),
      );
}
