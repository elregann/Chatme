// chat_reply.dart

import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/contact.dart';
import '../relay_manager.dart';
import '../room_chat.dart';

/// A message can be replied to once it is no longer a local placeholder.
/// Sending pictures (`temp_`) and queued pictures (`pending_`) are left out,
/// the same rule the swipe-to-reply gesture uses.
bool canReplyTo(ChatMessage message) =>
    !message.id.startsWith('temp_') && !message.id.startsWith('pending_');

/// One open chat screen that can receive a reply from another page.
class ChatScreenHandle {
  final String pubkey;
  final Route<dynamic> route;
  final ValueChanged<ChatMessage> onReply;

  const ChatScreenHandle({
    required this.pubkey,
    required this.route,
    required this.onReply,
  });
}

/// Finds the chat screen for a contact that is already in the page stack.
class ChatScreenRegistry {
  ChatScreenRegistry._();

  static final Map<String, ChatScreenHandle> _handles = {};

  static ChatScreenHandle? find(String pubkey) => _handles[pubkey];

  static void register(ChatScreenHandle handle) {
    _handles[handle.pubkey] = handle;
  }

  static void unregister(ChatScreenHandle handle) {
    if (identical(_handles[handle.pubkey], handle)) {
      _handles.remove(handle.pubkey);
    }
  }

  @visibleForTesting
  static void clear() => _handles.clear();
}

typedef ChatPageBuilder = Widget Function(
  Contact contact,
  RelayManager relayManager,
  ChatMessage initialReply,
);

/// Opens the chat for a picture and puts that picture in the reply preview.
///
/// An open chat for the same contact is reused instead of pushing a second
/// room chat on top of the stack.
class ChatReplyNavigator {
  final ChatPageBuilder buildChatPage;

  const ChatReplyNavigator({required this.buildChatPage});

  static final ChatReplyNavigator instance = ChatReplyNavigator(
    buildChatPage: (contact, relayManager, initialReply) => ChatDetailScreen(
      contact: contact,
      relayManager: relayManager,
      initialReply: initialReply,
    ),
  );

  void openReply(
    BuildContext context,
    ChatMessage message, {
    Contact? contact,
    RelayManager? relayManager,
  }) {
    if (!canReplyTo(message)) return;

    final peerPubkey =
        message.isMe ? message.receiverPubkey : message.senderPubkey;
    final openChat = ChatScreenRegistry.find(peerPubkey);

    if (openChat != null && openChat.route.isActive) {
      Navigator.of(context).popUntil((route) => route == openChat.route);
      openChat.onReply(message);
      return;
    }

    if (openChat != null) ChatScreenRegistry.unregister(openChat);
    if (contact == null || relayManager == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => buildChatPage(contact, relayManager, message),
      ),
    );
  }
}
