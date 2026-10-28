import 'package:flutter/material.dart';

import 'theme.dart';

/// What the customer allows right now, as the technician's client last heard it (FfiModel.permissions, updated live
/// when the customer switches something; Plan 13 F6). A permission never mentioned counts as allowed, as upstream does.
List<(String, bool)> permissionStates(Map<String, bool> p) => [
      ('موس و صفحه‌کلید', p['keyboard'] != false),
      ('کپی و چسباندن', p['clipboard'] != false),
      ('انتقال فایل', p['file'] != false),
    ];

/// A small strip at the bottom of the technician's remote window (UX-13), so "copy does not work" is not guesswork on
/// the phone. It never takes input.
class DolphinPermissionStrip extends StatelessWidget {
  final Map<String, bool> permissions;
  /// False until the peer info is set: an unknown permission counts as allowed, which would show a false all-green.
  final bool ready;
  const DolphinPermissionStrip({super.key, required this.permissions, this.ready = true});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(child: Builder(builder: _build), paint: false); // Dolphin Connect: light on any Windows theme (DR-1)

  Widget _build(BuildContext context) {
    if (!ready) return const SizedBox.shrink();
    final states = permissionStates(permissions);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: DolphinColors.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('اجازه‌های مشتری:', style: TextStyle(fontSize: 11.5, color: DolphinColors.muted)),
              for (final s in states) ...[
                const SizedBox(width: 10),
                Icon(s.$2 ? Icons.check_circle : Icons.block,
                    size: 14, color: s.$2 ? DolphinColors.aqua : DolphinColors.danger),
                const SizedBox(width: 4),
                Text(s.$1, style: TextStyle(fontSize: 11.5, color: s.$2 ? DolphinColors.ink : DolphinColors.dangerText)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
