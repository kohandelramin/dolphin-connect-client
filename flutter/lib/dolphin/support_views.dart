import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'health.dart';
import 'support_upload.dart';
import 'theme.dart';

/// Plan 18 Phase 4 on the customer home: the support tools (DD-38, DD-7, DD-48), the stopped-service notice (DD-19)
/// and the no-monitor notice (DD-40). Pure widgets: the work comes in as callbacks.

const kHealthLabel = 'بررسی سلامت';
const kReportLabel = 'گزارش برای پشتیبانی';
const kScreenshotLabel = 'عکس صفحه برای پشتیبانی';
const kSupportToolsTitle = 'کمک به کارشناس';

const kReportBody = 'گزارش‌های برنامه و وضعیت این رایانه برای کارشناس دلفین فرستاده می‌شود؛ بدون رمز و بدون شناسه‌ی رایانه‌های دیگر.';
const kScreenshotBody = 'این عکس صفحه‌ی شماست. اگر چیز خصوصی در آن پیداست، «انصراف» را بزنید.';
const kNoteLabel = 'توضیح کوتاه (اختیاری)';
const kSendLabel = 'فرستادن';
const kCancelLabel = 'انصراف';
const kCloseLabel = 'بستن';
const kPreparingReport = 'در حال آماده کردن گزارش…';
const kSendingLabel = 'در حال فرستادن…';
const kSaveReportLabel = 'ذخیره‌ی گزارش';
const kCheckAgainLabel = 'بررسی دوباره';
const kCheckingLabel = 'در حال بررسی…';

/// DD-19: under the red bar while the service is down; the button is upstream's own start (UAC prompt).
const kFixLabel = 'درست کن';

/// The three buttons on the home. A null callback hides its button (DD-7 and DD-48 follow `diagnostics-upload`).
class DolphinSupportTools extends StatelessWidget {
  final VoidCallback? onHealth;
  final VoidCallback? onReport;
  final VoidCallback? onScreenshot;
  const DolphinSupportTools({super.key, this.onHealth, this.onReport, this.onScreenshot});

  bool get isEmpty => onHealth == null && onReport == null && onScreenshot == null;

  @override
  Widget build(BuildContext context) {
    Widget button(String label, IconData icon, VoidCallback onPressed) => OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            foregroundColor: DolphinColors.azureText,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        );
    final onHealth = this.onHealth, onReport = this.onReport, onScreenshot = this.onScreenshot;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DolphinRadii.card),
        border: Border.all(color: DolphinColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(kSupportToolsTitle, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (onHealth != null) button(kHealthLabel, Icons.health_and_safety_outlined, onHealth),
          if (onReport != null) button(kReportLabel, Icons.summarize_outlined, onReport),
          if (onScreenshot != null) button(kScreenshotLabel, Icons.screenshot_monitor_outlined, onScreenshot),
        ]),
      ]),
    );
  }
}

/// DD-19: the service should run and does not.
class DolphinServiceNotice extends StatelessWidget {
  final String text;
  final VoidCallback? onFix;
  const DolphinServiceNotice({super.key, required this.text, this.onFix});

  @override
  Widget build(BuildContext context) {
    final onFix = this.onFix;
    return Container(
      key: const ValueKey('dolphin-service-notice'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: DolphinColors.dangerSoft,
        borderRadius: BorderRadius.circular(DolphinRadii.control),
        border: Border.all(color: DolphinColors.danger),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 18, color: DolphinColors.dangerText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: DolphinColors.dangerText, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.6)),
          ),
        ]),
        if (onFix != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onFix,
            icon: const Icon(Icons.build_outlined, size: 18),
            label: const Text(kFixLabel),
            style: FilledButton.styleFrom(backgroundColor: DolphinColors.dangerText, foregroundColor: Colors.white),
          ),
        ],
      ]),
    );
  }
}

/// DD-40: no monitor on this PC; what to do. Display only.
class DolphinHeadlessNotice extends StatelessWidget {
  final String fix;
  const DolphinHeadlessNotice({super.key, required this.fix});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('dolphin-headless-notice'),
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
        decoration: BoxDecoration(color: DolphinColors.amberSoft, borderRadius: BorderRadius.circular(DolphinRadii.control)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.desktop_access_disabled_outlined, size: 18, color: DolphinColors.amberText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kHeadlessTitle,
                  style: TextStyle(color: DolphinColors.amberText, fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(fix, style: TextStyle(color: DolphinColors.amberText, fontSize: 12, height: 1.6)),
            ]),
          ),
        ]),
      );
}

enum UploadPhase { ready, preparing, sending, done, failed }

/// DD-7 and DD-48 in their dialog: what is sent, the picture for DD-48 (the customer sees it before sending), an
/// optional note, «فرستادن» / «انصراف», then the portal's answer. Pure.
class DolphinUploadPanel extends StatelessWidget {
  final UploadKind kind;
  final UploadPhase phase;
  final String message;
  final Uint8List? png;
  final TextEditingController note;
  final VoidCallback onSend;
  final VoidCallback onClose;
  const DolphinUploadPanel(
      {super.key,
      required this.kind,
      required this.phase,
      required this.note,
      required this.onSend,
      required this.onClose,
      this.message = '',
      this.png});

  @override
  Widget build(BuildContext context) {
    final busy = phase == UploadPhase.preparing || phase == UploadPhase.sending;
    final done = phase == UploadPhase.done;
    final shot = kind == UploadKind.screenshot;
    final png = this.png;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(shot ? kScreenshotLabel : kReportLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(shot ? kScreenshotBody : kReportBody,
              style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
          if (png != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(DolphinRadii.field),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 170),
                decoration: BoxDecoration(border: Border.all(color: DolphinColors.line)),
                child: Image.memory(png, fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ),
          ],
          if (!done) ...[
            const SizedBox(height: 10),
            TextField(
              controller: note,
              enabled: !busy,
              maxLength: kUploadNoteMax,
              maxLines: 2,
              minLines: 1,
              decoration: InputDecoration(
                labelText: kNoteLabel,
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(DolphinRadii.field)),
              ),
            ),
          ],
          if (busy)
            Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(phase == UploadPhase.preparing ? kPreparingReport : kSendingLabel,
                  style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
            ]),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(message,
                  style: TextStyle(
                      color: done ? DolphinColors.aquaText : DolphinColors.dangerText, fontSize: 13, height: 1.6)),
            ),
          ],
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? null : onClose, child: Text(done ? kCloseLabel : kCancelLabel)),
            if (!done) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : onSend,
                style: FilledButton.styleFrom(backgroundColor: DolphinColors.azure, foregroundColor: Colors.white),
                child: const Text(kSendLabel),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// Prepares the bytes (DD-7 builds the zip only when «فرستادن» is pressed) and sends them with the note.
typedef UploadSend = Future<UploadAnswer> Function(String note);

/// The panel with its state.
class DolphinUploadForm extends StatefulWidget {
  final UploadKind kind;
  final Uint8List? png;
  final UploadSend onSend;
  final VoidCallback onClose;
  const DolphinUploadForm({super.key, required this.kind, required this.onSend, required this.onClose, this.png});

  @override
  State<DolphinUploadForm> createState() => _DolphinUploadFormState();
}

class _DolphinUploadFormState extends State<DolphinUploadForm> {
  final _note = TextEditingController();
  UploadPhase _phase = UploadPhase.ready;
  String _message = '';

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _phase = widget.kind == UploadKind.diagnostics ? UploadPhase.preparing : UploadPhase.sending;
      _message = '';
    });
    final answer = await widget.onSend(_note.text);
    if (!mounted) return;
    setState(() {
      _phase = answer.ok ? UploadPhase.done : UploadPhase.failed;
      _message = answer.text;
    });
  }

  @override
  Widget build(BuildContext context) => DolphinUploadPanel(
      kind: widget.kind,
      phase: _phase,
      message: _message,
      png: widget.png,
      note: _note,
      onSend: _send,
      onClose: widget.onClose);
}

Icon _toneIcon(CheckTone t) => switch (t) {
      CheckTone.ok => Icon(Icons.check_circle, size: 18, color: DolphinColors.aqua),
      CheckTone.warn => Icon(Icons.warning_amber_rounded, size: 18, color: DolphinColors.amberText),
      CheckTone.bad => Icon(Icons.cancel, size: 18, color: DolphinColors.dangerText),
      CheckTone.info => Icon(Icons.info_outline, size: 18, color: DolphinColors.muted),
    };

/// DD-38: the check list. Pure: [items] null while the checks run.
class DolphinHealthView extends StatelessWidget {
  final List<HealthItem>? items;
  final void Function(HealthFix fix)? onFix;
  final VoidCallback? onSave;
  final VoidCallback? onAgain;
  final VoidCallback onClose;

  /// After «ذخیره‌ی گزارش»: where it went, or why not.
  final String saved;
  const DolphinHealthView(
      {super.key, required this.items, required this.onClose, this.onFix, this.onSave, this.onAgain, this.saved = ''});

  @override
  Widget build(BuildContext context) {
    final items = this.items;
    final onFix = this.onFix;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text(kHealthLabel, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            IconButton(
                tooltip: kCloseLabel,
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: Icon(Icons.close, size: 20, color: DolphinColors.muted)),
          ]),
          if (items == null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text(kCheckingLabel, style: TextStyle(color: DolphinColors.muted, fontSize: 13)),
              ]),
            )
          else ...[
            Text(healthSummary(items),
                style: TextStyle(
                    color: items.any((i) => i.tone == CheckTone.bad) ? DolphinColors.dangerText : DolphinColors.aquaText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Column(children: [
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(padding: const EdgeInsets.only(top: 2), child: _toneIcon(i.tone)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(i.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                            Text(i.result,
                                style: TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.5)),
                            if (i.fix == HealthFix.startService && onFix != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: FilledButton.icon(
                                  onPressed: () => onFix(i.fix),
                                  icon: const Icon(Icons.build_outlined, size: 16),
                                  label: const Text(kFixServiceLabel),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: DolphinColors.azure, foregroundColor: Colors.white),
                                ),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
          ],
          if (saved.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(saved, style: TextStyle(color: DolphinColors.aquaText, fontSize: 12, height: 1.5)),
          ],
          const SizedBox(height: 8),
          if (items == null)
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: onClose, child: const Text(kCloseLabel)))
          else
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (onAgain != null) TextButton(onPressed: onAgain, child: const Text(kCheckAgainLabel)),
              if (onSave != null) ...[
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text(kSaveReportLabel),
                ),
              ],
            ]),
        ]),
      ),
    );
  }
}

/// The checks with their state: run on open and on «بررسی دوباره».
class DolphinHealthDialog extends StatefulWidget {
  final Future<List<HealthItem>> Function() run;
  final void Function(HealthFix fix) onFix;

  /// Saves the report of [items]; returns the line to show.
  final Future<String> Function(List<HealthItem> items) onSave;
  final VoidCallback onClose;
  const DolphinHealthDialog({super.key, required this.run, required this.onFix, required this.onSave, required this.onClose});

  @override
  State<DolphinHealthDialog> createState() => _DolphinHealthDialogState();
}

class _DolphinHealthDialogState extends State<DolphinHealthDialog> {
  List<HealthItem>? _items;
  String _saved = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _items = null;
      _saved = '';
    });
    final items = await widget.run();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _save() async {
    final items = _items;
    if (items == null) return;
    final line = await widget.onSave(items);
    if (mounted) setState(() => _saved = line);
  }

  @override
  Widget build(BuildContext context) => DolphinHealthView(
      items: _items, saved: _saved, onFix: widget.onFix, onSave: _save, onAgain: _run, onClose: widget.onClose);
}

/// Our dialogs in the small home window: nearly its full width (upstream's default margins leave 260 px).
Future<void> showDolphinPanel(BuildContext context, Widget Function(VoidCallback close) build) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DolphinLight(
        paint: false,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: build(() => Navigator.of(context).pop()),
          ),
        ),
      ),
    );
