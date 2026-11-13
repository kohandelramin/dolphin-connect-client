import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../dolphin/chat.dart'; // Dolphin Connect (DD-29)
import '../../mobile/pages/home_page.dart';

enum ChatPageType {
  mobileMain,
  desktopCM,
}

class ChatPage extends StatelessWidget implements PageShape {
  late final ChatModel chatModel;
  final ChatPageType? type;

  ChatPage({ChatModel? chatModel, this.type}) {
    this.chatModel = chatModel ?? gFFI.chatModel;
  }

  @override
  final title = translate("Chat");

  @override
  final icon = unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum);

  @override
  final appBarActions = [
    PopupMenuButton<MessageKey>(
        tooltip: "",
        icon: unreadTopRightBuilder(gFFI.chatModel.mobileUnreadSum,
            icon: Icon(Icons.group)),
        itemBuilder: (context) {
          // only mobile need [appBarActions], just bind gFFI.chatModel
          final chatModel = gFFI.chatModel;
          return chatModel.messages.entries.map((entry) {
            final key = entry.key;
            final user = entry.value.chatUser;
            final client = gFFI.serverModel.clients
                .firstWhereOrNull((e) => e.id == key.connId);
            final connected =
                gFFI.serverModel.clients.any((e) => e.id == key.connId);
            return PopupMenuItem<MessageKey>(
              child: Row(
                children: [
                  Icon(
                          key.isOut
                              ? Icons.call_made_rounded
                              : Icons.call_received_rounded,
                          color: MyTheme.accent)
                      .marginOnly(right: 6),
                  Text("${user.firstName}   ${user.id}"),
                  if (connected)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromARGB(255, 46, 205, 139)),
                    ).marginSymmetric(horizontal: 2),
                  if (client != null)
                    unreadMessageCountBuilder(client.unreadChatMessageCount)
                        .marginOnly(left: 4)
                ],
              ),
              value: key,
            );
          }).toList();
        },
        onSelected: (key) {
          gFFI.chatModel.changeCurrentKey(key);
        })
  ];

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: chatModel,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Consumer<ChatModel>(
          builder: (context, chatModel, child) {
            final readOnly = type == ChatPageType.mobileMain &&
                    (chatModel.currentKey.connId == ChatModel.clientModeID ||
                        gFFI.serverModel.clients.every((e) =>
                            e.id != chatModel.currentKey.connId ||
                            chatModel.currentUser == null)) ||
                type == ChatPageType.desktopCM &&
                    gFFI.serverModel.clients
                            .firstWhereOrNull(
                                (e) => e.id == chatModel.currentKey.connId)
                            ?.disconnected ==
                        true;
            return Stack(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final messages = chatModel
                          .messages[chatModel.currentKey]?.chatMessages ??
                      <ChatMessage>[];
                  final chat = DashChat(
                    onSend: chatModel.send,
                    currentUser: chatModel.me,
                    messages: messages,
                    readOnly: readOnly,
                    inputOptions: InputOptions(
                      inputTextDirection: TextDirection.rtl, // Dolphin Connect (DD-29)
                      focusNode: chatModel.inputNode,
                      textController: chatModel.textController,
                      inputTextStyle: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.titleLarge?.color),
                      inputDecoration: InputDecoration(
                        isDense: true,
                        hintText: translate('Write a message'),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.background,
                        contentPadding: EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                          borderSide: const BorderSide(
                            width: 1,
                            style: BorderStyle.solid,
                          ),
                        ),
                      ),
                      sendButtonBuilder: defaultSendButton(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                        color: MyTheme.accent,
                        icon: Icons.send_rounded,
                      ),
                    ),
                    messageOptions: MessageOptions(
                      showOtherUsersAvatar: false,
                      showOtherUsersName: false,
                      textColor: Colors.white,
                      maxWidth: constraints.maxWidth * 0.7,
                      // Dolphin Connect (DD-29): the text in its own direction, Persian time (flutter/lib/dolphin/chat.dart).
                      messageTextBuilder: (message, _, __) =>
                          DolphinChatText(text: message.text, at: message.createdAt),
                      messageDecorationBuilder:
                          (message, previousMessage, nextMessage) {
                        // Dolphin Connect (DD-29): ours on the left of the right-to-left chat, readable colours.
                        final ours = message.user.id == chatModel.me.id;
                        final c = chatBubbleCorners(ours: ours);
                        return defaultMessageDecoration(
                          color: ours ? kChatOurs : kChatTheirs,
                          borderTopLeft: c.topLeft,
                          borderTopRight: c.topRight,
                          borderBottomRight: c.bottomRight,
                          borderBottomLeft: c.bottomLeft,
                        );
                      },
                    ),
                  ).workaroundFreezeLinuxMint();
                  // Dolphin Connect (DD-29): right to left, Vazirmatn, «با فرستادن پیام شروع کنید» while empty.
                  return DolphinChatFrame(
                      empty: messages.isEmpty,
                      child: SelectionArea(child: chat));
                }),
              ],
            ).paddingOnly(bottom: 8);
          },
        ),
      ),
    );
  }
}
