import 'dart:async';

import '../tech/actions.dart';
import '../tech/state.dart';

/// Plan 19, code mode (TB-21): after «اتصال» on a PC of a code-mode organization the call waits for the customer's
/// one-time code, which the customer gives through the portal. While the card shows «در انتظار کد مشتری…» this asks
/// the portal every [every] for the card; when the call carries the code (`call.code`, assignee only) it opens the
/// session with it once. The technician can still type a code by hand. The code is never logged or kept.
class CodeModeWatcher {
  final PcCardController card;
  final Duration every;

  /// Called after a session was opened with the code (the shell remembers the PC for RO-8).
  final void Function(ConnectOutcome outcome)? onOutcome;

  CodeModeWatcher(this.card, {this.every = const Duration(seconds: 3), this.onOutcome}) {
    card.addListener(_check);
    _check();
  }

  Timer? _timer;
  bool _armed = false;
  bool _connecting = false;
  bool _disposed = false;
  final Set<String> _tried = {};

  /// The card should say «در انتظار کد مشتری…».
  bool get waiting => _armed && !_connecting;

  bool get _waitingNow => card.waitingForCode != null || (card.call?.waitingForCode ?? false);

  void _check() {
    if (_disposed) return;
    if (_waitingNow) _armed = true;
    final call = card.call;
    final code = call?.code;
    if (_armed && code != null && code.isNotEmpty && !(call?.sessionLive ?? false) && !_tried.contains(code)) {
      _tried.add(code);
      unawaited(_use(code));
      return;
    }
    if (_armed && !_connecting) {
      _timer ??= Timer.periodic(every, (_) {
        if (!card.loading && !card.busy) card.load();
      });
    } else {
      _stopTimer();
    }
  }

  Future<void> _use(String code) async {
    _connecting = true;
    _stopTimer();
    final o = card.waitingForCode != null ? await card.openWithCode(code) : await card.connect(password: code);
    if (_disposed) return;
    _connecting = false;
    if (o is Connected) {
      _armed = false;
    }
    if (o != null) onOutcome?.call(o);
    _check();
  }

  /// The technician typed the code.
  Future<ConnectOutcome?> typed(String text) async {
    final o = card.waitingForCode != null ? await card.openWithCode(text) : await card.connect(password: text);
    if (o is Connected) {
      _armed = false;
      _stopTimer();
    }
    if (o != null) onOutcome?.call(o);
    return o;
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _disposed = true;
    _stopTimer();
    card.removeListener(_check);
  }
}
