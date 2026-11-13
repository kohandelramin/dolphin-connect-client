import 'package:flutter/material.dart';

import 'digits.dart';
import 'theme.dart';

/// DD-29: the session chat, right to left, in both apps (upstream flutter/lib/common/widgets/chat_page.dart, hooks marked
/// `Dolphin Connect (DD-29)`). Vazirmatn, Persian time, a line while nothing has been said, and each message in its own
/// direction: a Windows path or an English error a customer pastes reads left to right inside the right-to-left chat.

const kChatEmpty = 'با فرستادن پیام شروع کنید';

/// The other side's bubble: white text 6.1:1 (upstream's blueGrey was 4.35:1). Ours is the brand azure (5.45:1).
Color get kChatTheirs => DolphinColors.muted;
Color get kChatOurs => DolphinColors.azure;

final _strongRtl = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');
final _strongLtr = RegExp(r'[A-Za-zÀ-ɏͰ-ϿЀ-ӿ]');

/// The direction of one message, from its first strong letter (as the Unicode bidi algorithm does for a paragraph);
/// digits and signs alone, or nothing, stay right to left.
TextDirection chatTextDirection(String text) {
  for (final rune in text.runes) {
    final c = String.fromCharCode(rune);
    if (_strongRtl.hasMatch(c)) return TextDirection.rtl;
    if (_strongLtr.hasMatch(c)) return TextDirection.ltr;
  }
  return TextDirection.rtl;
}

/// The time under a message, in Persian digits: «۹:۰۵».
String chatTime(DateTime t) => faDigits('${t.hour}:${t.minute.toString().padLeft(2, '0')}');

/// Corners of a bubble: the small corner points at the sender's side. In the right-to-left chat our messages sit on
/// the left (the line's end) and the other side's on the right (its start). Order: topLeft, topRight, bottomRight,
/// bottomLeft, as upstream's `defaultMessageDecoration` takes them.
({double topLeft, double topRight, double bottomRight, double bottomLeft}) chatBubbleCorners({required bool ours}) =>
    (topLeft: 8, topRight: 8, bottomRight: ours ? 8 : 2, bottomLeft: ours ? 2 : 8);

/// Around upstream's chat: right to left, Vazirmatn, and [kChatEmpty] in the middle while there are no messages. The
/// line ignores the pointer, so the input under it still works.
class DolphinChatFrame extends StatelessWidget {
  final bool empty;
  final Widget child;
  const DolphinChatFrame({super.key, required this.empty, required this.child});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).hintColor;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: kDolphinFont),
        child: Stack(children: [
          child,
          if (empty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  key: const ValueKey('dolphin-chat-empty'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 56), // above the input row
                    child: Text(kChatEmpty,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: kDolphinFont, color: muted, fontSize: 13, height: 1.7)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The inside of a bubble: the text in its own direction, the time under it.
class DolphinChatText extends StatelessWidget {
  final String text;
  final DateTime at;
  const DolphinChatText({super.key, required this.text, required this.at});

  @override
  Widget build(BuildContext context) {
    final dir = chatTextDirection(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            textDirection: dir,
            textAlign: dir == TextDirection.rtl ? TextAlign.right : TextAlign.left,
            style: const TextStyle(fontFamily: kDolphinFont, color: Colors.white, fontSize: 14, height: 1.6)),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(chatTime(at),
              style: const TextStyle(fontFamily: kDolphinFont, color: Colors.white, fontSize: 10)),
        ),
      ],
    );
  }
}

/// Whether an incoming message moves the chat to its sender (customer app, `ChatModel.receive`): when the chat still
/// shows a session that has ended (the ended tab stays for a minute, D15), the new technician's message would land
/// out of sight. A live conversation is never switched away from.
bool chatFollowsIncoming({required bool sameAsCurrent, required bool currentLive}) => !sameAsCurrent && !currentLive;
