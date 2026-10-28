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
  int _call = 0;

  /// The ID the waiting call was sent for; a result naming another ID belongs to an earlier call.
  String _id = '';

  /// Whether [token] (from [waiting]) is still the latest call.
  bool isCurrent(int token) => token == _call;

  /// The panel's answer: applied only while a call is waiting. A late one (after the timeout) changes nothing, and
  /// neither does one whose [id] is set and differs from the waiting call's. An empty [id] (older portal) is accepted.
  bool answer(String message, {required bool ok, String id = ''}) {
    if (!busy) return false;
    if (id.isNotEmpty && id != _id) return false;
    show(message, ok: ok);
    return true;
  }

  void show(String message, {required bool ok}) {
    _timer?.cancel();
    text = message;
    this.ok = ok;
    busy = false;
    notifyListeners();
  }

  int waiting({String id = ''}) {
    final token = ++_call;
    _id = id;
    show(kPanelChecking, ok: true);
    busy = true;
    _timer = Timer(wait, () => show(kPanelNoAnswer, ok: false));
    return token;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
