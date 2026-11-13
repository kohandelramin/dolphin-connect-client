import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../common.dart';
import 'call_status.dart';
import 'home_view.dart';
import 'tech_theme.dart';
import 'theme.dart';

/// The technician window's top row: brand, own ID, the manual connect field and «ظاهر» (DD-53). Every colour comes
/// from [DolphinTechPalette] of the app's brightness, so neither theme can turn the ID white on white (AUI-2).
class DolphinTechnicianHeader extends StatelessWidget {
  final String myId;
  final TextEditingController manual;
  final DolphinCallWait call;
  final VoidCallback onConnect;

  /// DD-53: the technician's theme choice; no switch when [onThemeMode] is null.
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeMode;

  const DolphinTechnicianHeader(
      {super.key,
      required this.myId,
      required this.manual,
      required this.call,
      required this.onConnect,
      this.themeMode = ThemeMode.system,
      this.onThemeMode});

  @override
  Widget build(BuildContext context) => DolphinTechTheme(child: Builder(builder: _build), paint: false);

  Widget _build(BuildContext context) {
    final p = DolphinTechPalette.ofContext(context);
    final fieldBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(DolphinRadii.field), borderSide: BorderSide(color: p.lineStrong));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.line))),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Text('دلفین کانکت', style: TextStyle(fontWeight: FontWeight.w800, color: p.accent)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(99)),
              child: Text('کارشناس', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.accent)),
            ),
            const SizedBox(width: 16),
            Text('شناسه‌ی شما', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(width: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(myId.isEmpty ? '…' : groupId(myId),
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.ink)),
            ),
            IconButton(
              tooltip: 'کپی شناسه',
              icon: Icon(Icons.copy, size: 16, color: p.muted),
              onPressed: myId.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: myId));
                      showToast('کپی شد');
                    },
            ),
            const Spacer(),
            SizedBox(
              width: 180,
              child: TextField(
                controller: manual,
                enabled: !call.busy,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: p.ink),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'شناسه‌ی مشتری',
                  hintStyle: TextStyle(color: p.muted),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                ),
                onSubmitted: (_) => onConnect(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: DolphinColors.azure,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.control))),
              onPressed: call.busy ? null : onConnect,
              child: const Text('اتصال'),
            ),
            if (onThemeMode != null) ...[
              const SizedBox(width: 4),
              DolphinThemeSwitch(mode: themeMode, onChanged: onThemeMode!),
            ],
          ],
        ),
      ),
    );
  }
}
