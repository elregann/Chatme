import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'notification_handler.dart';
import 'main.dart';
//fix
class ChatManager {
  static final ChatManager _instance = ChatManager._internal();
  factory ChatManager() => _instance;
  ChatManager._internal();

  static ChatManager get instance => _instance;
  final _lock = Lock();

  String getChatKey(String pubkey1, String pubkey2) {
    final sorted = [pubkey1, pubkey2]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }

  Future<ChatMessage?> getMessageById(String eventId, String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        final List<ChatMessage> messages = rawData.cast<ChatMessage>();
        for (var m in messages) {
          if (m.id == eventId) return m;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> isMessageExists(String messageId, String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        final List<ChatMessage> messages = rawData.cast<ChatMessage>();
        for (var m in messages) {
          if (m.id == messageId) return true;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> saveMessage(ChatMessage message) async {
    await _lock.synchronized(() async {
      try {
        final chatsBox = Hive.box('chats');
        final chatKey = message.chatKey.isNotEmpty
            ? message.chatKey
            : getChatKey(message.senderPubkey, message.receiverPubkey);

        final dynamic rawData = chatsBox.get(chatKey);
        List<ChatMessage> messages = [];
        if (rawData is List) {
          messages = rawData.cast<ChatMessage>().toList();
        }

        final existingIndex = messages.indexWhere((m) => m.id == message.id);

        const Map<String, int> statusWeight = {
          'error': -1,
          'sending': 0,
          'sent': 1,
          'read': 2,
        };

        if (existingIndex != -1) {
          final oldMsg = messages[existingIndex];

          final String finalStatus =
          (statusWeight[oldMsg.status] ?? 0) >
              (statusWeight[message.status] ?? 0)
              ? oldMsg.status
              : message.status;

          messages[existingIndex] = oldMsg.copyWith(
            status: finalStatus,
            replyToContent: message.replyToContent?.isNotEmpty == true
                ? message.replyToContent
                : oldMsg.replyToContent,
            plaintext: message.plaintext.isNotEmpty
                ? message.plaintext
                : oldMsg.plaintext,
            content: message.content.isNotEmpty
                ? message.content
                : oldMsg.content,
            timestamp: message.timestamp,
            reactions: message.reactions.isNotEmpty
                ? message.reactions
                : oldMsg.reactions,
          );
        } else {
          messages.add(message);
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

          final myPubkey = AppSettings.instance.myPubkey;
          if (message.senderPubkey != myPubkey) {
            final contactsBox = Hive.box<Contact>('contacts');
            final contact = contactsBox.get(message.senderPubkey);

            final senderName = contact != null
                ? contact.name
                : "User ${message.senderPubkey.substring(0, 8)}";

            final notificationId = message.timestamp % 2147483647;

            NotificationHandler.showNotification(
              id: notificationId,
              title: senderName,
              body: message.plaintext,
              payload: message.senderPubkey,
            );
          }
        }

        await chatsBox.put(chatKey, messages);
        await _updateContactPreview(message);
      } catch (e) {
        DebugLogger.log('❌ Error saving message: $e', type: 'ERROR');
      }
    });
  }

  Future<void> updateMessageStatus(String messageId, String newStatus,
      {String? chatKey}) async {
    await _lock.synchronized<void>(() async {
      try {
        final chatsBox = Hive.box('chats');

        if (chatKey != null && chatsBox.containsKey(chatKey)) {
          await _processStatusUpdate(
              chatsBox, chatKey, messageId, newStatus);
          return;
        }

        for (final key in chatsBox.keys) {
          await _processStatusUpdate(
              chatsBox, key.toString(), messageId, newStatus);
        }
      } catch (e) {
        DebugLogger.log('❌ Error updateMessageStatus: $e');
      }
    });
  }

  Future<void> _processStatusUpdate(
      Box box, String key, String id, String status) async {
    final dynamic rawData = box.get(key);
    if (rawData is List) {
      List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
      bool updated = false;

      const Map<String, int> statusWeight = {
        'error': -1,
        'sending': 0,
        'sent': 1,
        'read': 2,
      };

      for (var i = 0; i < messages.length; i++) {
        if (messages[i].id == id) {
          final msg = messages[i];

          final oldWeight = statusWeight[msg.status] ?? 0;
          final newWeight = statusWeight[status] ?? 0;

          if (newWeight <= oldWeight) break;

          messages[i] = msg.copyWithStatus(status);
          updated = true;
          break;
        }
      }

      if (updated) {
        await box.put(key, messages);
      }
    }
  }

  Future<void> _updateContactPreview(ChatMessage message) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final myPubkey = AppSettings.instance.myPubkey;

      final peerPubkey = (message.senderPubkey == myPubkey)
          ? message.receiverPubkey
          : message.senderPubkey;

      var contact = contactsBox.get(peerPubkey);

      if (contact != null) {
        if (message.timestamp >= contact.lastChatTime) {
          contact.lastMessage = message.plaintext;
          contact.lastChatTime = message.timestamp;
          await contactsBox.put(peerPubkey, contact);
        }
      }
    } catch (e) {
      DebugLogger.log('❌ Error updating contact preview: $e');
    }
  }

  Future<List<ChatMessage>> getMessages(String peerPubkey) async {
    try {
      final chatsBox = Hive.box('chats');
      final chatKey =
      getChatKey(AppSettings.instance.myPubkey, peerPubkey);
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        final messages = rawData.cast<ChatMessage>().toList();
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return messages;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<void> clearUnreadCount(String peerPubkey) async {
    await _lock.synchronized<void>(() async {
      try {
        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(peerPubkey);

        if (contact != null && contact.unreadCount > 0) {
          contact.unreadCount = 0;
          await contactsBox.put(peerPubkey, contact);
        }
      } catch (e) {}
    });
  }

  Future<void> deleteMessage(String messageId, String chatKey) async {
    await _lock.synchronized(() async {
      try {
        final chatsBox = Hive.box('chats');
        final dynamic rawData = chatsBox.get(chatKey);
        if (rawData is List) {
          List<ChatMessage> messages =
          rawData.cast<ChatMessage>().toList();
          messages.removeWhere((m) => m.id == messageId);
          await chatsBox.put(chatKey, messages);
          DebugLogger.log('🗑️ Message deleted: $messageId');
        }
      } catch (e) {}
    });
  }

  Future<void> deleteChatHistory(String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final settingsBox = Hive.box('settings');

      if (chatsBox.containsKey(chatKey)) {
        await chatsBox.delete(chatKey);
      }

      final parts = chatKey.split('_');
      if (parts.length == 3) {
        final myPubkey = AppSettings.instance.myPubkey;
        final peerPubkey =
        (parts[1] == myPubkey) ? parts[2] : parts[1];

        await settingsBox.put('cut_off_$peerPubkey',
            DateTime.now().millisecondsSinceEpoch);

        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(peerPubkey);

        if (contact != null) {
          contact.lastMessage = '';
          contact.lastChatTime = 0;
          contact.unreadCount = 0;
          await contactsBox.put(peerPubkey, contact);
        }
      }
      DebugLogger.log('🗑️ Chat dihapus & waktu cut-off dicatat untuk $chatKey');
    } catch (e) {
      DebugLogger.log('❌ Error deleteChatHistory: $e');
    }
  }

  Future<void> cleanupTempMessages() async {
    await _lock.synchronized<void>(() async {
      try {
        final chatsBox = Hive.box('chats');
        for (final key in chatsBox.keys) {
          final dynamic rawData = chatsBox.get(key);
          if (rawData is List) {
            List<ChatMessage> messages =
            rawData.cast<ChatMessage>().toList();
            final filtered =
            messages.where((m) => !m.id.startsWith('temp_')).toList();
            if (filtered.length != messages.length) {
              await chatsBox.put(key, filtered);
            }
          }
        }
      } catch (e) {}
    });
  }

  Future<void> repairReplyContent(
      String originalMsgId, String originalText, String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final dynamic rawData = chatsBox.get(chatKey);

      if (rawData is List) {
        List<ChatMessage> messages =
        rawData.cast<ChatMessage>().toList();
        bool adaYangBerubah = false;

        for (int i = 0; i < messages.length; i++) {
          if (messages[i].replyToId == originalMsgId &&
              (messages[i].replyToContent == null ||
                  messages[i].replyToContent!.isEmpty)) {
            messages[i] =
                messages[i].copyWith(replyToContent: originalText);
            adaYangBerubah = true;
          }
        }

        if (adaYangBerubah) {
          await chatsBox.put(chatKey, messages);
        }
      }
    } catch (e) {}
  }
}