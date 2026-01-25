import 'dart:async';
import 'package:hive_flutter/hive_flutter.dart';
import 'notification_handler.dart';
import 'main.dart';

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

  // Ambil pesan berdasarkan ID (Optimasi scannability)
  Future<ChatMessage?> getMessageById(String eventId, String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        // Gunakan cast untuk performa pembacaan
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

  // Cek apakah pesan sudah ada
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

  // Simpan pesan ke storage (Optimasi Notifikasi & Sinkronisasi)
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

        if (existingIndex != -1) {
          // UPDATE PESAN YANG SUDAH ADA (Misal dari relay lain)
          final oldMsg = messages[existingIndex];

          // Lindungi konten reply agar tidak hilang saat update
          String? protectedReplyContent = (message.replyToContent == null || message.replyToContent!.isEmpty)
              ? oldMsg.replyToContent
              : message.replyToContent;

          // Hitung bobot status agar tidak mundur (misal 'read' tidak tertimpa 'sent')
          const Map<String, int> statusWeight = {
            'error': -1, 'sending': 0, 'sent': 1, 'delivered': 2, 'read': 3,
          };

          String finalStatus = message.status;
          int oldWeight = statusWeight[oldMsg.status] ?? 0;
          int newWeight = statusWeight[message.status] ?? 0;

          if (oldWeight > newWeight) {
            finalStatus = oldMsg.status;
          }

          messages[existingIndex] = message.copyWith(
            replyToContent: protectedReplyContent,
            status: finalStatus,
          );
        } else {
          // PESAN BENAR-BENAR BARU
          messages.add(message);
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

          // Notifikasi hanya dipicu di sini (mencegah duplikasi dari banyak relay)
          final myPubkey = AppSettings.instance.myPubkey;
          if (message.senderPubkey != myPubkey) {
            final contactsBox = Hive.box<Contact>('contacts');
            final contact = contactsBox.get(message.senderPubkey);

            String senderName = contact != null
                ? contact.name
                : "User ${message.senderPubkey.substring(0, 8)}";

            int notificationId = message.timestamp % 2147483647;

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

  // Update status pesan (Optimasi: Langsung ke chatKey jika tersedia)
  Future<void> updateMessageStatus(String messageId, String newStatus, {String? chatKey}) async {
    await _lock.synchronized<void>(() async {
      try {
        final chatsBox = Hive.box('chats');

        // Jika chatKey diberikan (dari RelayManager), langsung proses (Turbo Mode)
        if (chatKey != null && chatsBox.containsKey(chatKey)) {
          await _processStatusUpdate(chatsBox, chatKey, messageId, newStatus);
          return;
        }

        // Jika chatKey tidak ada, baru cari manual (Fallback Mode)
        for (final key in chatsBox.keys) {
          await _processStatusUpdate(chatsBox, key.toString(), messageId, newStatus);
        }
      } catch (e) {
        DebugLogger.log('❌ Error updateMessageStatus: $e');
      }
    });
  }

  // Helper internal untuk update status tanpa redundansi kode
  Future<void> _processStatusUpdate(Box box, String key, String id, String status) async {
    final dynamic rawData = box.get(key);
    if (rawData is List) {
      List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
      bool updated = false;

      for (var i = 0; i < messages.length; i++) {
        if (messages[i].id == id) {
          final msg = messages[i];

          // Proteksi agar status tidak turun kasta (misal: dari read jadi sent)
          if (msg.status == 'read') return;
          if (msg.status == 'delivered' && status == 'sent') return;

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

  // Update preview kontak (Optimasi: unread count lebih akurat)
  Future<void> _updateContactPreview(ChatMessage message) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final myPubkey = AppSettings.instance.myPubkey;

      final peerPubkey = (message.senderPubkey == myPubkey)
          ? message.receiverPubkey
          : message.senderPubkey;

      var contact = contactsBox.get(peerPubkey);

      if (contact != null) {
        // Update data jika pesan ini lebih baru dari data di kontak
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

  // Ambil semua pesan dengan kontak tertentu (Optimasi sorting)
  Future<List<ChatMessage>> getMessages(String peerPubkey) async {
    try {
      final chatsBox = Hive.box('chats');
      final chatKey = getChatKey(AppSettings.instance.myPubkey, peerPubkey);
      final dynamic rawData = chatsBox.get(chatKey);
      if (rawData is List) {
        final messages = rawData.cast<ChatMessage>().toList();
        // Hive terkadang mengembalikan data tidak urut, pastikan urut di sini
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return messages;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Reset counter unread
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

  // Hapus pesan tunggal
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
      } catch (e) {}
    });
  }

  // Hapus seluruh history chat
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
        final peerPubkey = (parts[1] == myPubkey) ? parts[2] : parts[1];

        // Catat waktu cut-off agar pesan lama tidak ditarik lagi oleh relay
        await settingsBox.put('cut_off_$peerPubkey', DateTime.now().millisecondsSinceEpoch);

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

  // Bersihkan pesan temporary
  Future<void> cleanupTempMessages() async {
    await _lock.synchronized<void>(() async {
      try {
        final chatsBox = Hive.box('chats');
        for (final key in chatsBox.keys) {
          final dynamic rawData = chatsBox.get(key);
          if (rawData is List) {
            List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
            final filtered = messages.where((m) => !m.id.startsWith('temp_')).toList();
            if (filtered.length != messages.length) {
              await chatsBox.put(key, filtered);
            }
          }
        }
      } catch (e) {}
    });
  }

  // Perbaiki konten reply yang hilang (Optimasi pencarian)
  Future<void> repairReplyContent(String originalMsgId, String originalText, String chatKey) async {
    try {
      final chatsBox = Hive.box('chats');
      final dynamic rawData = chatsBox.get(chatKey);

      if (rawData is List) {
        List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();
        bool adaYangBerubah = false;

        for (int i = 0; i < messages.length; i++) {
          if (messages[i].replyToId == originalMsgId &&
              (messages[i].replyToContent == null || messages[i].replyToContent!.isEmpty)) {

            messages[i] = messages[i].copyWith(replyToContent: originalText);
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