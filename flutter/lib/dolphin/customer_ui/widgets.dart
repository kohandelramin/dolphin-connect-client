import 'package:flutter/material.dart';

import '../theme.dart';
import 'format.dart';

/// Plan 19 C4: the small pieces the customer's request screens share. Colours only from [DolphinColors] (theme tokens),
/// so the customer's light and dark (C5) and a theme the portal pushes reach every screen.

/// The strip at the top of each screen: «بازگشت» (when there is somewhere to go back to), the title, and [trailing].
class CustomerBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  /// LTR titles («#۱۲۴» reads the same either way; a username would not).
  final TextDirection? titleDirection;
  const CustomerBar({super.key, required this.title, this.onBack, this.trailing, this.titleDirection});

  @override
  Widget build(BuildContext context) {
    final onBack = this.onBack, trailing = this.trailing;
    return Container(
      decoration: BoxDecoration(color: DolphinColors.surface, border: Border(bottom: BorderSide(color: DolphinColors.line))),
      padding: EdgeInsetsDirectional.fromSTEB(onBack == null ? 14 : 4, 4, 10, 4),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        if (onBack != null)
          TextButton.icon(
            key: const ValueKey('c4-back'),
            onPressed: onBack,
            // Mirrored in RTL: points right, «→ بازگشت» as the design and the web portal draw it.
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('بازگشت'),
            style: TextButton.styleFrom(foregroundColor: DolphinColors.muted, padding: const EdgeInsets.symmetric(horizontal: 10)),
          ),
        if (onBack != null) const SizedBox(width: 2),
        Expanded(
          child: Text(title,
              textDirection: titleDirection,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: DolphinColors.ink)),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }
}

enum NoticeTone { info, warning, error, success }

/// A one-paragraph notice in the portal's tones (Notice in the web).
class CustomerNotice extends StatelessWidget {
  final String text;
  final NoticeTone tone;
  const CustomerNotice(this.text, {super.key, this.tone = NoticeTone.info});

  @override
  Widget build(BuildContext context) {
    final (fg, bg, icon) = switch (tone) {
      NoticeTone.info => (DolphinColors.azureText, DolphinColors.azureSoft, Icons.info_outline),
      NoticeTone.warning => (DolphinColors.amberText, DolphinColors.amberSoft, Icons.info_outline),
      NoticeTone.error => (DolphinColors.dangerText, DolphinColors.dangerSoft, Icons.error_outline),
      NoticeTone.success => (DolphinColors.aquaText, DolphinColors.aquaSoft, Icons.check_circle_outline),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(DolphinRadii.control)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: fg)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 12.5, height: 1.6, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}

/// A request's state as a small chip.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (statusTone(status)) {
      StatusTone.active => (DolphinColors.aquaText, DolphinColors.aquaSoft),
      StatusTone.done => (DolphinColors.aquaText, DolphinColors.aquaSoft),
      StatusTone.neutral => (DolphinColors.muted, DolphinColors.ground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: DolphinColors.line)),
      child: Text(statusLabel(status), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// A labelled field (the design's small label above the input).
class CustomerField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final String? hint;
  final TextDirection? direction;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;
  final bool autofocus;
  const CustomerField(
      {super.key,
      required this.label,
      required this.controller,
      this.obscure = false,
      this.enabled = true,
      this.minLines = 1,
      this.maxLines = 1,
      this.maxLength,
      this.hint,
      this.direction,
      this.onSubmitted,
      this.fieldKey,
      this.autofocus = false});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: TextStyle(color: DolphinColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          key: fieldKey,
          controller: controller,
          obscureText: obscure,
          enabled: enabled,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: obscure ? 1 : maxLines,
          maxLength: maxLength,
          textDirection: direction,
          onSubmitted: onSubmitted,
          style: TextStyle(color: DolphinColors.ink, fontSize: 14),
          decoration: customerInput(hint: hint),
        ),
      ]);
}

/// The fields' look: the surface, the field radius, the strong line, azure when focused.
InputDecoration customerInput({String? hint}) {
  OutlineInputBorder edge(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(DolphinRadii.field), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: DolphinColors.surface,
    hintText: hint,
    hintStyle: TextStyle(color: DolphinColors.muted, fontSize: 13.5),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: edge(DolphinColors.lineStrong),
    enabledBorder: edge(DolphinColors.lineStrong),
    disabledBorder: edge(DolphinColors.line),
    focusedBorder: edge(DolphinColors.azure, 1.5),
  );
}

/// A centred, quiet line while something loads.
class CustomerLoading extends StatelessWidget {
  final String text;
  const CustomerLoading({super.key, this.text = 'در حال خواندن…'});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: DolphinColors.azure)),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: DolphinColors.muted, fontSize: 13)),
        ]),
      );
}
