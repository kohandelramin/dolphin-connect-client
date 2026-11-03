import 'dart:convert';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Pushed by the portal (app/src/lib/engine/policy.ts CALLBACK_OPTION, Plan 14 B6): "Y" on a PC linked to an
/// organization, where «با من تماس بگیرید» can open a request; anything else hides the button.
const kDolphinCallbackOption = 'dolphin-callback';
const kCallbackLabel = 'با من تماس بگیرید';

bool callbackShown(String option) => option == 'Y';

String _latin(String s) => s.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
      final c = m[0]!.codeUnitAt(0);
      return String.fromCharCode(0x30 + (c >= 0x06F0 ? c - 0x06F0 : c - 0x0660));
    });

/// Same rule as src/dolphin_callback_core.rs, so the customer hears about a typo before anything is sent.
String? callbackProblem(String name, String phone) {
  final n = name.trim();
  if (n.isEmpty || n.characters.length > 60) return 'نام خود را بنویسید (حداکثر ۶۰ نویسه).';
  final p = _latin(phone).replaceAll(RegExp(r'[\s\-().]'), '');
  if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(p)) return 'شماره‌ی تلفن را درست بنویسید؛ مثلاً ۰۹۱۲۳۴۵۶۷۸۹.';
  return null;
}

enum CallbackPhase { idle, sending, done, failed }

class CallbackStatus {
  final CallbackPhase phase;
  final String text;
  const CallbackStatus(this.phase, [this.text = '']);

  /// From src/dolphin_callback.rs `state()`. Anything unexpected reads as idle.
  factory CallbackStatus.fromJson(String raw) {
    try {
      final v = jsonDecode(raw);
      final phase = switch (v['state']) {
        'sending' => CallbackPhase.sending,
        'done' => CallbackPhase.done,
        'failed' => CallbackPhase.failed,
        _ => CallbackPhase.idle,
      };
      return CallbackStatus(phase, v['text'] is String ? v['text'] as String : '');
    } catch (_) {
      return const CallbackStatus(CallbackPhase.idle);
    }
  }
}

typedef CallbackSend = Future<CallbackStatus> Function(String name, String phone, String note);

/// The form in its dialog: name, phone, an optional line about the problem. Pure: sending is [onSend]'s job.
class DolphinCallbackForm extends StatefulWidget {
  final CallbackSend onSend;
  final VoidCallback onClose;
  const DolphinCallbackForm({super.key, required this.onSend, required this.onClose});

  @override
  State<DolphinCallbackForm> createState() => _DolphinCallbackFormState();
}

class _DolphinCallbackFormState extends State<DolphinCallbackForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  CallbackStatus _status = const CallbackStatus(CallbackPhase.idle);
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final problem = callbackProblem(_name.text, _phone.text);
    setState(() => _problem = problem);
    if (problem != null) return;
    setState(() => _status = const CallbackStatus(CallbackPhase.sending));
    final result = await widget.onSend(_name.text.trim(), _phone.text.trim(), _note.text.trim());
    if (mounted) setState(() => _status = result);
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(DolphinRadii.field)),
      );

  @override
  Widget build(BuildContext context) {
    final done = _status.phase == CallbackPhase.done;
    final sending = _status.phase == CallbackPhase.sending;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(kCallbackLabel, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('کارشناس دلفین به این شماره زنگ می‌زند و بعد به همین رایانه وصل می‌شود.',
              style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, height: 1.6)),
          const SizedBox(height: 12),
          if (!done) ...[
            TextField(controller: _name, enabled: !sending, decoration: _field('نام شما')),
            const SizedBox(height: 8),
            TextField(
                controller: _phone,
                enabled: !sending,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: _field('شماره‌ی تلفن')),
            const SizedBox(height: 8),
            TextField(controller: _note, enabled: !sending, maxLength: 500, maxLines: 2, decoration: _field('مشکل چیست؟ (اختیاری)')),
          ],
          if (_problem != null) Text(_problem!, style: const TextStyle(color: DolphinColors.dangerText, fontSize: 12.5)),
          if (_status.text.isNotEmpty)
            Text(_status.text,
                style: TextStyle(color: done ? DolphinColors.aquaText : DolphinColors.dangerText, fontSize: 13, height: 1.6)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: sending ? null : widget.onClose, child: Text(done ? 'بستن' : 'انصراف')),
            if (!done) ...[
              const SizedBox(width: 8),
              FilledButton(
                onPressed: sending ? null : _send,
                style: FilledButton.styleFrom(backgroundColor: DolphinColors.azure, foregroundColor: Colors.white),
                child: Text(sending ? 'در حال فرستادن…' : 'فرستادن'),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// The form in a dialog. Here, not in home.dart: upstream's common.dart has its own `Dialog`.
Future<void> showDolphinCallback(BuildContext context, CallbackSend onSend) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: DolphinCallbackForm(onSend: onSend, onClose: () => Navigator.of(context).pop()),
        ),
      ),
    );
