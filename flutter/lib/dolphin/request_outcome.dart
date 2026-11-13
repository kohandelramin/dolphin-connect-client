import 'dart:async';

import 'package:flutter/material.dart';

import 'digits.dart';
import 'theme.dart';

/// DD-14: the technician app says plainly what became of a connection request that waits for the customer's «پذیرفتن»:
/// «مشتری رد کرد» when the customer pressed «رد», «مشتری جواب نداد» when nobody has answered for a while. Only words:
/// the request keeps waiting exactly as before (upstream has no time limit on it), and «لغو» ends it as before.
/// Hooks: `FfiModel.handleMsgBox` (flutter/lib/models/model.dart) and `showWaitAcceptDialog`
/// (flutter/lib/common/widgets/dialog.dart), marked `Dolphin Connect (DD-14)`.

/// The key the refusal is shown with; its Persian text is in dolphin/rebrand.py FA_ADD (same pattern as
/// `dolphin_share_stopped`), so msgboxContent translates it like any other connection error.
const kDolphinRequestDeniedKey = 'dolphin_request_denied';

/// After this long without an answer the wait says «مشتری جواب نداد».
const kDolphinNoAnswerAfter = Duration(seconds: 60);

const kDolphinWaitingTitle = 'منتظر پذیرفتن مشتری';
const kDolphinNoAnswerTitle = 'مشتری جواب نداد';
const kDolphinNoAnswerHint =
    'با مشتری تماس بگیرید تا در پنجره‌ی دلفین کانکت «پذیرفتن» را بزند؛ درخواست هنوز باز است. یا «لغو» را بزنید و بعد دوباره وصل شوید.';

/// The close reason the customer's «رد» sends: the CM's `Data::Close` before any login
/// (src/server/connection.rs `send_close_reason_no_retry("")`). The same words after a login mean «پایان».
const _closedByPeer = 'Closed manually by the peer';

/// Whether this message box is the customer refusing the request: the technician app, a request that was waiting for
/// «پذیرفتن» (no login since), and the peer's manual close.
bool dolphinRequestDenied({
  required bool technician,
  required bool waitingForAccept,
  required String title,
  required String text,
}) =>
    technician && waitingForAccept && title == 'Connection Error' && text == _closedByPeer;

/// The wait line: how long it has waited, in Persian digits («۱۲ ثانیه» or «۱:۰۵»).
String dolphinWaitedText(Duration waited) {
  final s = waited.isNegative ? 0 : waited.inSeconds;
  if (s < 60) return faDigits('$s ثانیه');
  return faDigits('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}');
}

/// The waiting dialog's content in the technician app: «منتظر پذیرفتن مشتری» with the time, then after
/// [kDolphinNoAnswerAfter] «مشتری جواب نداد» and what to do. [now] is for tests.
class DolphinWaitAccept extends StatefulWidget {
  final DateTime Function() now;
  final Duration noAnswerAfter;
  DolphinWaitAccept({super.key, DateTime Function()? now, this.noAnswerAfter = kDolphinNoAnswerAfter})
      : now = now ?? DateTime.now;

  @override
  State<DolphinWaitAccept> createState() => _DolphinWaitAcceptState();
}

class _DolphinWaitAcceptState extends State<DolphinWaitAccept> {
  late final DateTime _since = widget.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waited = widget.now().difference(_since);
    final noAnswer = waited >= widget.noAnswerAfter;
    // Colour only on the icon; the text keeps the dialog's own colours, so it reads on a light or a dark window.
    final color = noAnswer ? DolphinColors.msgError : DolphinColors.azure;
    final muted = Theme.of(context).hintColor;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(noAnswer ? Icons.phone_missed_outlined : Icons.hourglass_top, size: 40, color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(noAnswer ? kDolphinNoAnswerTitle : kDolphinWaitingTitle,
                key: const ValueKey('dolphin-wait-title'),
                style: const TextStyle(fontFamily: kDolphinFont, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 4),
            Text(dolphinWaitedText(waited),
                style: TextStyle(fontFamily: kDolphinFont, color: muted, fontSize: 12.5)),
            if (noAnswer)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(kDolphinNoAnswerHint,
                    style: TextStyle(fontFamily: kDolphinFont, fontSize: 13, height: 1.7)),
              ),
          ]),
        ),
      ]),
    );
  }
}
