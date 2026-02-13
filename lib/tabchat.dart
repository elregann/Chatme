import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'roomchat.dart';
import 'relaymanager.dart';
import 'chatmanager.dart';
import 'main.dart';
import 'package:flutter/services.dart';

class ChatsScreen extends StatefulWidget {
  final RelayManager relayManager;

  const ChatsScreen({super.key, required this.relayManager});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    widget.relayManager.onMessageReceived = () {
      if (mounted) setState(() {});
    };

    widget.relayManager.onMessageDelivered = (eventId) {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Color _getAvatarColor(String pubkey) {
    return Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "?";
    return name.trim().substring(0, 1).toUpperCase();
  }

  Widget _buildHighlightedText(String text, String query, bool isDark) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)
      );
    }

    final List<TextSpan> spans = [];
    final String lowercaseText = text.toLowerCase();
    final String lowercaseQuery = query.toLowerCase();

    int start = 0;
    int indexOfHighlight;

    while ((indexOfHighlight = lowercaseText.indexOf(lowercaseQuery, start)) != -1) {
      // Teks sebelum bagian yang di-highlight
      if (indexOfHighlight > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfHighlight)));
      }

      // Bagian yang di-highlight (kasih background biru)
      spans.add(TextSpan(
        text: text.substring(indexOfHighlight, indexOfHighlight + query.length),
        style: TextStyle(
          /// backgroundColor: Colors.blue.withAlpha(100), // Background biru transparan
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = indexOfHighlight + query.length;
    }

    // Sisa teks setelah highlight terakhir
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
        children: spans,
      ),
    );
  }

  Widget _buildStatusIcon(String status, Color color) {
    switch (status) {
      case 'pending':
      case 'sending':
        return Icon(Icons.access_time_rounded, size: 13, color: color.withAlpha(120));
      case 'sent':
        return Icon(Icons.done, size: 13, color: color.withAlpha(153));
      case 'read':
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF34B7F1));
      case 'error':
        return const Icon(Icons.error_outline, size: 13, color: Colors.redAccent);
      default:
        return Icon(Icons.done, size: 13, color: color.withAlpha(153));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myPubkey = AppSettings.instance.myPubkey;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chats'),
          elevation: 0,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(10),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search contact or messages',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = "";
                        });
                        _searchFocusNode.unfocus();
                      },
                    )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.only(top: 10),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<Box<Contact>>(
                valueListenable: Hive.box<Contact>('contacts').listenable(),
                builder: (context, contactBox, _) {
                  return ValueListenableBuilder(
                    valueListenable: Hive.box('chats').listenable(),
                    builder: (context, Box chatBox, _) {
                      final myPubkey = AppSettings.instance.myPubkey;
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final contactList = contactBox.values.toList();

                      // --- 1. LOGIKA FILTER CONTACTS (Hanya yang di-save) ---
                      List<Contact> filteredSavedContacts = [];
                      if (_searchQuery.isNotEmpty) {
                        filteredSavedContacts = contactList.where((c) {
                          return c.isSaved && c.name.toLowerCase().contains(_searchQuery);
                        }).toList();
                      }

                      // --- 2. LOGIKA FILTER CHATS (Berdasarkan Nama/Pubkey) ---
                      List<Map<String, dynamic>> chatPreviews = [];
                      // --- 3. LOGIKA FILTER MESSAGES (Scan isi pesan) ---
                      List<Map<String, dynamic>> messageResults = [];

                      for (var contact in contactList) {
                        final String displayName = contact.isSaved
                            ? contact.name
                            : 'User ${contact.pubkey.substring(0, 8)}';

                        // Ambil pesan dari box
                        final chatKey = ChatManager.instance.getChatKey(myPubkey, contact.pubkey);
                        final dynamic rawData = chatBox.get(chatKey);
                        List<ChatMessage> messages = rawData is List ? rawData.cast<ChatMessage>().toList() : [];

                        // Cek apakah nama cocok untuk kategori CHATS
                        bool nameMatches = _searchQuery.isNotEmpty &&
                            (displayName.toLowerCase().contains(_searchQuery) ||
                                contact.pubkey.toLowerCase().contains(_searchQuery));

                        // Cek isi pesan untuk kategori MESSAGES (minimal 3 huruf biar ringan)
                        if (_searchQuery.length >= 2) {
                          for (var m in messages) {
                            if (m.plaintext.toLowerCase().contains(_searchQuery)) {
                              messageResults.add({
                                'contact': contact,
                                'message': m,
                              });
                            }
                          }
                        }

                        // Logika untuk menyusun Preview Chat (seperti biasa)
                        int latestTime = contact.lastChatTime;
                        ChatMessage? lastMessage;

                        if (messages.isNotEmpty) {
                          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                          lastMessage = messages.last;
                          latestTime = lastMessage.timestamp;
                        }

                        // Masukkan ke daftar Chat jika ada pesan atau nama cocok saat dicari
                        if ((messages.isNotEmpty || contact.lastChatTime > 0) &&
                            (_searchQuery.isEmpty || nameMatches)) {
                          chatPreviews.add({
                            'contact': contact,
                            'lastMsg': lastMessage,
                            'time': latestTime,
                          });
                        }
                      }

                      // Urutkan chat berdasarkan waktu terbaru
                      chatPreviews.sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));

                      // Jika semua kosong
                      if (chatPreviews.isEmpty && filteredSavedContacts.isEmpty && messageResults.isEmpty) {
                        return _searchQuery.isEmpty ? _buildEmptyState() : _buildNoResultState();
                      }

                      return ListView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          // ================= SEKSI CONTACTS =================
                          if (_searchQuery.isNotEmpty && filteredSavedContacts.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text("CONTACTS", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                            ),
                            ...filteredSavedContacts.map((contact) => _buildContactItem(contact, null)).toList(),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, thickness: 0.1)),
                          ],

                          // ================= SEKSI CHATS =================
                          if (chatPreviews.isNotEmpty) ...[
                            if (_searchQuery.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Text("CHATS", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                              ),
                            ...chatPreviews.map((item) => _buildContactItem(
                                item['contact'] as Contact,
                                item['lastMsg'] as ChatMessage?
                            )).toList(),
                            if (_searchQuery.isNotEmpty && messageResults.isNotEmpty)
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, thickness: 0.1)),
                          ],

                          // ================= SEKSI MESSAGES (Tanpa Ikon) =================
                          if (_searchQuery.isNotEmpty && messageResults.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text("MESSAGES", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                            ),
                            ...messageResults.map((res) {
                              final contact = res['contact'] as Contact;
                              final msg = res['message'] as ChatMessage;
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                title: Text(
                                  contact.isSaved ? contact.name : "User ${contact.pubkey.substring(0,8)}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                                ),
                                subtitle: Row(
                                  children: [
                                    if (msg.senderPubkey == myPubkey) // Cek kalau itu pesan kita
                                      Text(
                                          "You: ",
                                          style: TextStyle(
                                              color: Colors.blue.withAlpha(150),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14
                                          )
                                      ),
                                    Expanded(
                                      child: _buildHighlightedText(msg.plaintext, _searchQuery, isDark),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => ChatDetailScreen(
                                    contact: contact,
                                    relayManager: widget.relayManager,
                                  )));
                                },
                              );
                            }).toList(),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 70, color: Colors.grey.withAlpha(100)),
          const SizedBox(height: 16),
          Text(
            'No results for "$_searchQuery"',
            style: const TextStyle(color: Colors.grey, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(Contact contact, ChatMessage? lastMsg) {
    final myPubkey = AppSettings.instance.myPubkey;
    final String displayName = contact.isSaved
        ? contact.name
        : 'User ${contact.pubkey.substring(0, 8)}';

    final isMe = lastMsg?.senderPubkey == myPubkey;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: _getAvatarColor(contact.pubkey),
        child: Text(
          _getInitials(displayName),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            if (lastMsg != null && isMe) ...[
              _buildStatusIcon(lastMsg.status, isDark ? Colors.white70 : Colors.black54),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                lastMsg != null ? lastMsg.plaintext : 'Tap to start chatting',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: isMe ? Colors.grey : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TimeUtils.formatTimeHumanized(lastMsg?.timestamp ?? contact.lastChatTime),
            style: TextStyle(
                fontSize: 11,
                color: contact.unreadCount > 0 ? Colors.grey : Colors.grey
            ),
          ),
          const SizedBox(height: 4),
          if (contact.unreadCount > 0)
            Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                  '${contact.unreadCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold
                  )
              ),
            )
          else
            const SizedBox(height: 18),
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 80, color: Colors.grey.withAlpha(50)),
          const SizedBox(height: 20),
          const Text('No conversations yet', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _showDeleteDialog(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Ikon Tong Sampah (Gaya Lingkaran Transparan)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Clear Chat History?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),

            // Penjelasan yang lebih informatif
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(180),
                    height: 1.5,
                    fontFamily: 'sans-serif'
                ),
                children: [
                  const TextSpan(text: 'This will permanently delete all messages with '),
                  TextSpan(
                    text: contact.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const TextSpan(text: '.\n'),
                  const TextSpan(
                    text: 'This action cannot be undone.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons ala gaya Restore
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Keep Chat', style: TextStyle(color: Colors.grey[600])),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Delete All', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final myPubkey = AppSettings.instance.myPubkey;
      final chatKey = ChatManager.instance.getChatKey(myPubkey, contact.pubkey);
      await ChatManager.instance.deleteChatHistory(chatKey);
      if (!contact.isSaved) await Hive.box<Contact>('contacts').delete(contact.pubkey);
      HapticFeedback.vibrate(); // Getar lebih kuat sebagai tanda penghapusan
    }

    _searchFocusNode.unfocus();
  }
}