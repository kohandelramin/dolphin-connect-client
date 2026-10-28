import 'dart:async';

import 'package:flutter/material.dart';

import 'panel_bridge.dart';
import 'theme.dart';

/// The line under the technician app's «اتصال» field: what the panel said about the ID (WF-2).
class DolphinCallStatus extends StatelessWidget {
  final String text;
  final bool ok;
  const DolphinCallStatus({super.key, required this.text, required this.ok});

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          color: ok ? DolphinColors.azureSoft : DolphinColors.dangerSoft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5, height: 1.6, color: ok ? DolphinColors.azureStrong : DolphinColors.dangerText)),
        ),
      );
}

/// The field's wait for the panel. The portal sends no answer while it is busy or when the staff sign-in has
/// expired, so the app times out itself: after [wait] it says [kPanelNoAnswer] and the field works again.
class DolphinCallWait extends ChangeNotifier {
  final Duration wait;
  DolphinCallWait(this.wait);

  String? text;
  bool ok = false;

  /// True from the moment the panel is asked until an answer or the timeout; the field is disabled meanwhile.
  bool busy = false;
  Timer? _timer;

  void show(String message, {required bool ok}) {
    _timer?.cancel();
    text = message;
    this.ok = ok;
    busy = false;
    notifyListeners();
  }

  void waiting() {
    show(kPanelChecking, ok: true);
    busy = true;
    _timer = Timer(wait, () => show(kPanelNoAnswer, ok: false));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
