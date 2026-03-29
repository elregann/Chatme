// chat_manager.dart

import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'notification_handler.dart';
import 'services/app_settings.dart';
import 'models/contact.dart';
import 'core/utils/debug_logger.dart';
import 'models/chat_message.dart';
import 'services/nostr_service.dart';
import 'relay_manager.dart';

class ChatManager {
  static final ChatManager _instance = ChatManager._internal();
  factory ChatManager() => _instance;
  ChatManager._internal();

  static ChatManager get instance => _instance;
  final _lock = Lock();

  static const Map<String, int> _statusWeight = {
    'pending': -2,
    'error': -1,
    'sending': 0,
    'sent': 1,
    'read': 2,
  };

  int _getStatusWeight(String status) => _statusWeight[status] ?? 0;

  String getChatKey(String pubkey1, String pubkey2) {
    final sorted = [pubkey1, pubkey2]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }

  Future<ChatMessage?> getMessageById(String eventId, String chatKey) async {
    try {
      final raw = Hive.box('chats').get(chatKey);
      if (raw is List) {
        final messages = raw.cast<ChatMessage>();
        return messages.firstWhere((m) => m.id == eventId);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> isMessageExists(String messageId, String chatKey) async {
    try {
      final raw = Hive.box('chats').get(chatKey);
      if (raw is List) {
        return raw.cast<ChatMessage>().any((m) => m.id == messageId);
      }
    } catch (_) {}
    return false;
  }

  Future<void> saveMessage(ChatMessage message) async {
    await _lock.synchronized(() async {
      try {
        final chatsBox = Hive.box('chats');
        final chatKey = message.chatKey.isNotEmpty
            ? message.chatKey
            : getChatKey(message.senderPubkey, message.receiverPubkey);

        final dynamic rawData = chatsBox.get(chatKey);
        List<ChatMessage> messages = (rawData is List)
            ? rawData.cast<ChatMessage>().toList()
            : [];

        final existingIndex = messages.indexWhere((m) => m.id == message.id);

        if (existingIndex != -1) {
          final oldMsg = messages[existingIndex];
          final String finalStatus = (_getStatusWeight(oldMsg.status) > _getStatusWeight(message.status))
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

          if (message.senderPubkey != AppSettings.instance.myPubkey) {
            Future.microtask(() => _triggerNotification(message));
          }
        }

        await chatsBox.put(chatKey, messages);
        await _updateContactPreview(message);
      } catch (e) {
        DebugLogger.log('❌ Error saving message: $e', type: 'ERROR');
      }
    });
  }

  void _triggerNotification(ChatMessage message) async {
    try {
      final settingsBox = Hive.box('settings');
      final eventId = message.id;

      // Cek apakah eventId ini sudah dinotifikasi via FCM
      final alreadyNotified = settingsBox.get('notified_$eventId', defaultValue: false) as bool;
      if (alreadyNotified) {
        // Hapus flag, skip show notif
        await settingsBox.delete('notified_$eventId');
        return;
      }

      // Belum dinotifikasi, show notif seperti biasa
      final contact = Hive.box<Contact>('contacts').get(message.senderPubkey);
      final senderName = contact?.name ?? AppSettings.formatDisplayName(message.senderPubkey);
      NotificationHandler.showChatNotification(
        senderPubkey: message.senderPubkey,
        senderName: senderName,
        message: message.plaintext,
      );
    } catch (e) {
      DebugLogger.log('❌ Error _triggerNotification: $e', type: 'ERROR');
    }
  }

  static Future<void> sendReplyFromNotification({
    required String receiverPubkey,
    required String plaintext,
    required RelayManager relayManager,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = ChatManager.instance.getChatKey(myPubkey, receiverPubkey);
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

      final tempMessage = ChatMessage(
        id: tempId,
        senderPubkey: myPubkey,
        receiverPubkey: receiverPubkey,
        content: '',
        plaintext: plaintext,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'sending',
        chatKey: chatKey,
      );

      await ChatManager.instance.saveMessage(tempMessage);

      final event = await relayManager.sendMessage(
        receiverPubkey: receiverPubkey,
        plaintext: plaintext,
      );

      final realMessage = tempMessage.copyWith(
        id: event['id'].toString(),
        content: event['content'].toString(),
        status: 'sending',
      );

      await ChatManager.instance.saveMessage(realMessage);
      await ChatManager.instance.deleteMessage(tempId, chatKey);
      NotificationHandler.clearNotification(receiverPubkey);

    } catch (e) {
      DebugLogger.log('❌ sendReplyFromNotification error: $e', type: 'ERROR');
    }
  }

  Future<void> updateMessageStatus(String messageId, String newStatus, {String? chatKey}) async {
    await _lock.synchronized<void>(() async {
      try {
        final chatsBox = Hive.box('chats');
        if (chatKey != null && chatsBox.containsKey(chatKey)) {
          await _processStatusUpdate(chatsBox, chatKey, messageId, newStatus);
        } else {
          for (final key in chatsBox.keys) {
            await _processStatusUpdate(chatsBox, key.toString(), messageId, newStatus);
          }
        }
      } catch (e) {
        DebugLogger.log('❌ Error updateMessageStatus: $e');
      }
    });
  }

  Future<void> _processStatusUpdate(Box box, String key, String id, String status) async {
    final dynamic rawData = box.get(key);
    if (rawData is List) {
      List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
      bool updated = false;

      for (var i = 0; i < messages.length; i++) {
        if (messages[i].id == id) {
          if (_getStatusWeight(status) > _getStatusWeight(messages[i].status)) {
            messages[i] = messages[i].copyWithStatus(status);
            updated = true;
          }
          break;
        }
      }
      if (updated) await box.put(key, messages);
    }
  }

  Future<List<ChatMessage>> getPendingMessages() async {
    List<ChatMessage> pendingQueue = [];
    try {
      final chatsBox = Hive.box('chats');
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var key in chatsBox.keys) {
        final dynamic rawData = chatsBox.get(key);
        if (rawData is List) {
          for (var m in rawData.cast<ChatMessage>()) {
            if (m.status == 'pending' || (m.status == 'sending' && (now - m.timestamp) > 10000)) {
              pendingQueue.add(m);
            }
          }
        }
      }
      pendingQueue.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    } catch (e) {
      DebugLogger.log('❌ Error getPendingMessages: $e');
    }
    return pendingQueue;
  }

  Future<void> updateMessageIdAndStatus(String oldId, String newId, String status, String chatKey) async {
    await _lock.synchronized(() async {
      try {
        final chatsBox = Hive.box('chats');
        final dynamic rawData = chatsBox.get(chatKey);
        if (rawData is List) {
          List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
          final index = messages.indexWhere((m) => m.id == oldId);
          if (index != -1) {
            messages[index] = messages[index].copyWith(id: newId, status: status);
            await chatsBox.put(chatKey, messages);
            DebugLogger.log('🆔 ID Updated: $oldId -> $newId ($status)');
          }
        }
      } catch (e) {
        DebugLogger.log('❌ Error updateMessageIdAndStatus: $e');
      }
    });
  }

  Future<void> _updateContactPreview(ChatMessage message) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final myPubkey = AppSettings.instance.myPubkey;
      final peerPubkey = (message.senderPubkey == myPubkey) ? message.receiverPubkey : message.senderPubkey;

      var contact = contactsBox.get(peerPubkey);
      if (contact != null && message.timestamp >= contact.lastChatTime) {
        contact.lastMessage = message.plaintext;
        contact.lastChatTime = message.timestamp;
        await contactsBox.put(peerPubkey, contact);
      }
    } catch (e) {
      DebugLogger.log('❌ Error updating contact preview: $e');
    }
  }

  Future<List<ChatMessage>> getMessages(String peerPubkey) async {
    try {
      final chatsBox = Hive.box('chats');
      final chatKey = getChatKey(AppSettings.instance.myPubkey, peerPubkey);
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        final messages = rawData.cast<ChatMessage>().toList();
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return messages;
      }
    } catch (_) {}
    return [];
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
      } catch (_) {}
    });
  }

  Future<void> deleteMessage(String messageId, String chatKey) async {
    await _lock.synchronized(() async {
      try {
        final chatsBox = Hive.box('chats');
        final dynamic rawData = chatsBox.get(chatKey);
        if (rawData is List) {
          List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
          messages.removeWhere((m) => m.id == messageId);
          await chatsBox.put(chatKey, messages);
          DebugLogger.log('🗑️ Message deleted: $messageId');
        }
      } catch (_) {}
    });
  }

  Future<void> deleteChatHistory(String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      if (chatsBox.containsKey(chatKey)) await chatsBox.delete(chatKey);

      final parts = chatKey.split('_');
      if (parts.length == 3) {
        final myPubkey = AppSettings.instance.myPubkey;
        final peerPubkey = (parts[1] == myPubkey) ? parts[2] : parts[1];
        await Hive.box('settings').put('cut_off_$peerPubkey', DateTime.now().millisecondsSinceEpoch);

        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(peerPubkey);
        if (contact != null) {
          contact.lastMessage = '';
          contact.lastChatTime = 0;
          contact.unreadCount = 0;
          await contactsBox.put(peerPubkey, contact);
        }
      }
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
            List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
            final filtered = messages.where((m) => !m.id.startsWith('temp_')).toList();
            if (filtered.length != messages.length) await chatsBox.put(key, filtered);
          }
        }
      } catch (_) {}
    });
  }

  Future<void> repairReplyContent(String originalMsgId, String originalText, String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
        bool changed = false;
        for (int i = 0; i < messages.length; i++) {
          if (messages[i].replyToId == originalMsgId && (messages[i].replyToContent?.isEmpty ?? true)) {
            messages[i] = messages[i].copyWith(replyToContent: originalText);
            changed = true;
          }
        }
        if (changed) await chatsBox.put(chatKey, messages);
      }
    } catch (_) {}
  }
}