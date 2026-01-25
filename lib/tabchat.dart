import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'roomchat.dart';
import 'relaymanager.dart';
import 'chatmanager.dart';
import 'main.dart';

class ChatsScreen extends StatefulWidget {
  final RelayManager relayManager;

  const ChatsScreen({super.key, required this.relayManager});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  @override
  void initState() {
    super.initState();
    widget.relayManager.onMessageReceived = () {
      if (mounted) {
        setState(() {});
        DebugLogger.log('🔔 ChatsScreen: Database updated, UI refreshing via Hive');
      }
    };

    widget.relayManager.onMessageDelivered = (eventId) {
      if (mounted) {
        _updateMessageStatus(eventId, 'delivered');
        setState(() {}); // Centang langsung berubah di layar
      }
    };
  }

  // Generate warna avatar berdasarkan pubkey
  Color _getAvatarColor(String pubkey) {
    return Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);
  }

  // Ambil inisial nama untuk avatar
  String _getInitials(String name) {
    if (name.trim().isEmpty) return "?";
    return name.trim().substring(0, 1).toUpperCase();
  }

  // Update status pesan
  void _updateMessageStatus(String eventId, String status) async {
    try {
      await ChatManager.instance.updateMessageStatus(eventId, status);
    } catch (e) {
      DebugLogger.log('❌ Error updating status: $e', type: 'ERROR');
    }
  }

  // Widget icon status pesan
  Widget _buildStatusIcon(String status, Color color) {
    switch (status) {
      case 'sending': return Icon(Icons.access_time, size: 13, color: color.withAlpha(153));
      case 'sent': return Icon(Icons.done, size: 13, color: color.withAlpha(153));
      case 'delivered': return Icon(Icons.done_all, size: 13, color: color.withAlpha(153));
      case 'read': return const Icon(Icons.done_all, size: 13, color: Color(0xFF34B7F1));
      default: return Icon(Icons.done, size: 13, color: color.withAlpha(153));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myPubkey = AppSettings.instance.myPubkey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: const [],
      ),
      body: ValueListenableBuilder<Box<Contact>>(
        valueListenable: Hive.box<Contact>('contacts').listenable(),
        builder: (context, contactBox, _) {
          return ValueListenableBuilder(
            valueListenable: Hive.box('chats').listenable(),
            builder: (context, Box chatBox, _) {

              final contactList = contactBox.values.toList();
              List<Map<String, dynamic>> chatPreviews = [];

              for (var contact in contactList) {
                final chatKey = ChatManager.instance.getChatKey(myPubkey, contact.pubkey);
                final dynamic rawData = chatBox.get(chatKey);
                List<ChatMessage> messages = rawData is List ? rawData.cast<ChatMessage>().toList() : [];

                int latestTime = contact.lastChatTime;
                ChatMessage? lastMessage;

                if (messages.isNotEmpty) {
                  messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                  lastMessage = messages.last;
                  latestTime = lastMessage.timestamp;
                }

                if (messages.isNotEmpty || contact.lastChatTime > 0) {
                  chatPreviews.add({
                    'contact': contact,
                    'lastMsg': lastMessage,
                    'time': latestTime,
                  });
                }
              }

              chatPreviews.sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));

              if (chatPreviews.isEmpty) return _buildEmptyState();

              return ListView.builder(
                itemCount: chatPreviews.length,
                itemBuilder: (context, index) {
                  final item = chatPreviews[index];
                  return _buildContactItem(
                      item['contact'] as Contact,
                      item['lastMsg'] as ChatMessage?
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // Widget item kontak dalam list
  Widget _buildContactItem(Contact contact, ChatMessage? lastMsg) {
    final myPubkey = AppSettings.instance.myPubkey;
    final String displayName = contact.isSaved
        ? contact.name
        : 'User ${contact.pubkey.substring(0, 8)}';

    final isMe = lastMsg?.senderPubkey == myPubkey;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getAvatarColor(contact.pubkey),
        child: Text(
          _getInitials(displayName),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(
        displayName,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Row(
        children: [
          if (lastMsg != null && isMe) ...[
            _buildStatusIcon(lastMsg.status, Colors.grey),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              lastMsg != null ? lastMsg.plaintext : 'Tap to start chatting',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe ? Colors.grey : null,
              ),
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            TimeUtils.formatTimeHumanized(lastMsg?.timestamp ?? contact.lastChatTime),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          // GANTI BAGIAN INI DI DALAM trailing: Column
          if (contact.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 20,  // Lebar tetap agar bulat
              height: 20, // Tinggi tetap agar bulat
              alignment: Alignment.center, // Supaya angka tepat di tengah
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle, // Membuat lingkaran sempurna
              ),
              child: Text(
                  '${contact.unreadCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10, // Ukuran font diperkecil sedikit agar pas di dalam lingkaran
                      fontWeight: FontWeight.bold
                  )
              ),
            ),
        ],
      ),
      onLongPress: () => _showDeleteDialog(contact),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              contact: contact,
              relayManager: widget.relayManager,
            ),
          ),
        );
      },
    );
  }

  // Widget state kosong
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Theme.of(context).disabledColor),
          const SizedBox(height: 20),
          const Text('No conversations yet'),
        ],
      ),
    );
  }

  // Dialog konfirmasi hapus chat
  Future<void> _showDeleteDialog(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('All messages with this contact will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = ChatManager.instance.getChatKey(myPubkey, contact.pubkey);
      await ChatManager.instance.deleteChatHistory(chatKey);
      if (!contact.isSaved) await Hive.box<Contact>('contacts').delete(contact.pubkey);
    }
  }
}