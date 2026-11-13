import 'dart:async';

import 'package:flutter/material.dart';

import '../common.dart';
import '../models/model.dart';
import '../models/platform_model.dart';
import 'brand.dart';
import 'home.dart' show kDolphinSupportPhoneOption;
import 'safe_mode.dart';
import 'support_views.dart' show showDolphinPanel;
import 'home_view.dart' show supportPhone;

/// Plan 18 Phase 5 (DD-11): the wiring of safe_mode.dart. The technician's toolbar entry and its answers
/// (session_toolbar_hook.dart, models/model.dart `handleMsgBox`), the customer's «حالت امن» banner (home.dart).

// ---- the technician ----

/// What the customer's PC said at login (`platform_additions`); null while it said nothing (an older app).
bool? _addition(FFI ffi, String key) {
  final v = ffi.ffiModel.pi.platformAdditions[key];
  return v is bool ? v : null;
}

/// The toolbar's entry for this session, or null.
DolphinRestartKind? dolphinSafeModeEntry(FFI ffi) => safeModeEntry(
    peerInSafeMode: _addition(ffi, kDolphinSafeModeAddition), peerOffers: _addition(ffi, kDolphinSafeModeOffered));

final _replyTimers = Expando<Timer>('dolphin-safe-mode-reply');

String _tag(FFI ffi) => '${ffi.sessionId}-dolphin-safe-mode';

/// The toolbar entry: the technician confirms, then the PC is asked; its answers come through [dolphinSafeModeMsgBox].
void dolphinSafeModeAsk(FFI ffi, DolphinRestartKind kind) {
  ffi.dialogManager.dismissByTag(_tag(ffi));
  ffi.dialogManager.show(
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: DolphinSafeModeAskView(
        kind: kind,
        onConfirm: () {
          close();
          bind.sessionSetCommon(sessionId: ffi.sessionId, key: kDolphinSafeModeKey, value: restartCode(kind));
          _replyTimers[ffi]?.cancel();
          _replyTimers[ffi] = Timer(kDolphinSafeModeReplyWait,
              () => _showAnswer(ffi, const SafeModeAnswer(SafeModeTone.warn, kSafeModeNoReply)));
        },
        onCancel: close,
      ),
      onCancel: close,
    ),
    tag: _tag(ffi),
  );
}

void _showAnswer(FFI ffi, SafeModeAnswer answer) {
  if (ffi.closed) return;
  ffi.dialogManager.dismissByTag(_tag(ffi));
  ffi.dialogManager.show(
    (setState, close, context) => CustomAlertDialog(
      title: null,
      content: DolphinSafeModeAnswerView(answer: answer, onClose: close),
      onCancel: close,
    ),
    tag: _tag(ffi),
  );
}

/// The PC's answer (`MessageBox` of type [kDolphinSafeModeKey]) in one dialog per session, the newest replacing the
/// last. True: taken, upstream does nothing more with it.
bool dolphinSafeModeMsgBox(FFI? ffi, dynamic type, dynamic title, dynamic text) {
  final answer = safeModeAnswerFromMsgBox(type, title, text);
  if (answer == null || ffi == null) return false;
  _replyTimers[ffi]?.cancel();
  _showAnswer(ffi, answer);
  return true;
}

// ---- the customer ----

/// The customer's home in Safe Mode: the banner with «بازگشت به حالت عادی», asked once when the window opens. Nothing
/// at all on a normal boot.
class DolphinSafeModeHome extends StatefulWidget {
  const DolphinSafeModeHome({super.key});

  @override
  State<DolphinSafeModeHome> createState() => _DolphinSafeModeHomeState();
}

class _DolphinSafeModeHomeState extends State<DolphinSafeModeHome> {
  bool _safe = false;
  bool _asking = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    if (!isWindows) return;
    final safe = await bind.mainGetCommon(key: 'dolphin-safe-mode') == 'Y';
    if (mounted && safe != _safe) setState(() => _safe = safe);
  }

  Future<void> _return() async {
    var ok = false;
    await showDolphinPanel(
        context,
        (close) => DolphinSafeModeReturnConfirm(onConfirm: () {
              ok = true;
              close();
            }, onCancel: close));
    if (!ok || !mounted) return;
    setState(() => _asking = true);
    final code = await bind.mainGetCommon(key: 'dolphin-normal-restart');
    final phone = supportPhone(bind.mainGetOptionSync(key: kDolphinSupportPhoneOption), DolphinBrand.supportPhone);
    if (!mounted) return;
    setState(() {
      _note = customerReturnText(code, phone);
      // Pressed again only if the service did not take it.
      _asking = code == 'restarting' || code == 'busy';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_safe) return const SizedBox.shrink();
    return DolphinSafeModeBanner(onReturn: _asking ? null : _return, note: _note);
  }
}
