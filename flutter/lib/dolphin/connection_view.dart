import 'package:flutter/material.dart';

import 'theme.dart';
import 'verify.dart';

typedef DolphinAccept = void Function(bool keyboard, bool clipboard, bool file);

/// The prompt a customer answers before a technician gets in. File transfer starts off. The name shown is the
/// one the portal vouches for ([verdict]); a peer the portal did not authorize gets no Accept button.
class DolphinAcceptView extends StatefulWidget {
  final TechVerdict verdict;
  final String peerName;
  final DolphinAccept onAccept;
  final VoidCallback onDeny;
  final bool showElevate;
  final DolphinAccept? onAcceptElevate;

  const DolphinAcceptView(
      {super.key,
      required this.verdict,
      required this.peerName,
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
    final state = widget.verdict.state;
    final canAccept = state == TechCheck.verified || state == TechCheck.unverifiable;
    final (String title, String note, Color color, IconData icon) = switch (state) {
      TechCheck.verified => (
          '${widget.verdict.name.isEmpty ? widget.peerName : widget.verdict.name} از دلفین',
          'کارشناس تأییدشده‌ی دلفین می‌خواهد به این رایانه وصل شود',
          DolphinColors.azure,
          Icons.verified_user,
        ),
      TechCheck.checking => ('در حال بررسی هویت کارشناس…', 'چند لحظه صبر کنید', DolphinColors.muted, Icons.hourglass_top),
      TechCheck.unverifiable => (
          widget.peerName,
          'هویت کارشناس قابل بررسی نیست؛ فقط اگر همین حالا پشت تلفن با کارشناس دلفین هستید بپذیرید',
          const Color(0xFFB45309),
          Icons.help_outline,
        ),
      TechCheck.rejected => (
          'این اتصال از کارشناس دلفین نیست',
          'دلفین برای این رایانه اتصالی ثبت نکرده است؛ «رد» را بزنید',
          DolphinColors.danger,
          Icons.gpp_bad,
        ),
    };
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(radius: 22, backgroundColor: color, child: Icon(icon, color: Colors.white)),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: state == TechCheck.rejected ? DolphinColors.danger : null)),
            Text(note, textAlign: TextAlign.center, style: const TextStyle(color: DolphinColors.muted)),
            const SizedBox(height: 12),
            if (canAccept) Wrap(
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
              if (canAccept)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: DolphinColors.azure),
                    onPressed: () => widget.onAccept(keyboard, clipboard, file),
                    child: const Text('پذیرفتن'),
                  ),
                ),
              if (canAccept) const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton(
                      onPressed: widget.onDeny, child: const Text('رد'))),
            ]),
            if (canAccept && widget.showElevate && onAcceptElevate != null)
              TextButton(
                onPressed: () => onAcceptElevate(keyboard, clipboard, file),
                child: const Text('پذیرفتن با اجازه‌ی مدیر ویندوز'),
              ),
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
