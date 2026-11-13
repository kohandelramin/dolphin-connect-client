import 'package:flutter/material.dart';

import 'theme.dart';

/// Plan 19, the customer app's new look: one row with a label and a switch (C1 «اشتراک‌گذاری», C2 and C3 permissions,
/// C5 settings). The whole row is the target, 40 px tall at least. [onChanged] null shows it dimmed (a choice the
/// organization made); [note] is a short line under the label.
class DolphinSwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? note;
  final Color? noteColor;
  final Key? switchKey;
  const DolphinSwitchRow(
      {super.key, required this.label, required this.value, this.onChanged, this.note, this.noteColor, this.switchKey});

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final note = this.note;
    return Semantics(
      toggled: value,
      label: label,
      enabled: onChanged != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(DolphinRadii.field),
        onTap: onChanged == null ? null : () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: TextStyle(
                        color: onChanged == null ? DolphinColors.muted : DolphinColors.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                if (note != null && note.isNotEmpty)
                  Text(note, style: TextStyle(color: noteColor ?? DolphinColors.muted, fontSize: 11.5, height: 1.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Switch(
              key: switchKey,
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Two or three choices side by side (C2 «کامل» / «فقط تماشا», C5 theme). [selected] null lights none (a hand-made
/// mix of permissions).
class DolphinSegmented<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T> onSelected;
  final String keyPrefix;
  const DolphinSegmented(
      {super.key, required this.options, required this.selected, required this.onSelected, this.keyPrefix = 'dolphin-seg'});

  @override
  Widget build(BuildContext context) {
    final r = Radius.circular(DolphinRadii.field);
    return Container(
      decoration: BoxDecoration(
        color: DolphinColors.azureSoft,
        borderRadius: BorderRadius.all(r),
        border: Border.all(color: DolphinColors.line),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (value, label) in options)
          Semantics(
            button: true,
            selected: value == selected,
            child: Material(
              color: value == selected ? DolphinColors.azure : Colors.transparent,
              borderRadius: BorderRadius.all(r),
              child: InkWell(
                key: ValueKey('$keyPrefix-$value'),
                borderRadius: BorderRadius.all(r),
                onTap: () => onSelected(value),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 34, minWidth: 72),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Center(
                      widthFactor: 1,
                      child: Text(label,
                          style: TextStyle(
                              color: value == selected ? DolphinColors.onFill : DolphinColors.azureText,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
