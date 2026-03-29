// tab_contact.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'room_chat.dart';
import 'relay_manager.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'models/contact.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/ui_utils.dart';
import 'ui/contacts/add_contact.dart';
import 'package:remixicon/remixicon.dart';

class ContactsScreen extends StatefulWidget {
  final RelayManager relayManager;
  const ContactsScreen({super.key, required this.relayManager});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";

  List<Map<String, String>> _globalSearchResults = [];
  bool _isSearchingGlobal = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _searchGlobalUser(String query) async {
    if (query.length < 2) {
      setState(() {
        _globalSearchResults = [];
        _isSearchingGlobal = false;
      });
      return;
    }

    setState(() => _isSearchingGlobal = true);

    try {
      // Panggil Database
      final url = Uri.parse('https://chatme-412d1-default-rtdb.asia-southeast1.firebasedatabase.app/usernames.json');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic>? data = jsonDecode(response.body);
        List<Map<String, String>> results = [];

        if (data != null) {
          data.forEach((username, pubkey) {
            if (username.toLowerCase().contains(query.toLowerCase())) {
              results.add({
                'username': username,
                'pubkey': pubkey.toString(),
              });
            }
          });
        }

        setState(() {
          _globalSearchResults = results;
          _isSearchingGlobal = false;
        });
      }
    } catch (e) {
      DebugLogger.log('❌ Global Search Error: $e', type: 'ERROR');
      setState(() => _isSearchingGlobal = false);
    }
  }

  Future<void> _quickAddFromGlobal(String name, String pubkey) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final contact = Contact(
        pubkey: pubkey,
        name: name,
        isSaved: true,
        lastChatTime: 0,
        lastMessage: '',
        unreadCount: 0,
      );
      await contactsBox.put(pubkey, contact);
      HapticFeedback.mediumImpact();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$name added to contacts',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _searchController.clear();
        setState(() => _searchQuery = "");
      }
    } catch (e) {
      DebugLogger.log('❌ Quick Add Error: $e', type: 'ERROR');
    }
  }

  // Add Contact
  Future<void> _addContact() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddContactPage()),
    );
  }

  // Hapus kontak
  Future<void> _deleteContact(Contact contact) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Remove contact',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contact.name,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withAlpha(30), width: 0.5),
                    ),
                    child: Icon(Remix.user_minus_fill, size: 18, color: Colors.red.withAlpha(200)),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Divider
              Divider(height: 0.5, thickness: 0.5, color: borderColor),

              const SizedBox(height: 16),

              // Info
              Text(
                'Chat history will remain after removal.',
                style: TextStyle(fontSize: 13, color: textSecondary, height: 1.5),
              ),

              const SizedBox(height: 20),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor, width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(fontSize: 13, color: textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withAlpha(40), width: 0.5),
                        ),
                        child: Center(
                          child: Text(
                            'Remove',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red.withAlpha(200),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final contactsBox = Hive.box<Contact>('contacts');
      if (contact.lastMessage.isNotEmpty) {
        contact.isSaved = false;
        await contactsBox.put(contact.pubkey, contact);
      } else {
        await contactsBox.delete(contact.pubkey);
      }
      DebugLogger.log('Contact removed from list: ${contact.name}', type: 'UI');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Contacts',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: Theme.of(context).iconTheme.color,
            ),
          ),
          elevation: 0,
        ),
        body: Column(
          children: [
            // --- UI SEARCH BAR ---
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

                    // Debouncing: Tunggu user berhenti ngetik selama 500ms baru cari ke Firebase
                    if (_debounce?.isActive ?? false) _debounce!.cancel();
                    _debounce = Timer(const Duration(milliseconds: 500), () {
                      _searchGlobalUser(_searchQuery);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search people by ID or name',
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

            // --- LIST AREA ---
            Expanded(
              child: ValueListenableBuilder<Box<Contact>>(
                valueListenable: Hive.box<Contact>('contacts').listenable(),
                builder: (context, box, _) {
                  // Filter lokal berdasarkan search query
                  final contacts = box.values
                      .where((c) => c.isSaved == true)
                      .where((c) => _searchQuery.isEmpty || c.name.toLowerCase().contains(_searchQuery))
                      .toList();

                  contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                  if (contacts.isEmpty && _searchQuery.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      // SEKSI "GLOBAL SEARCH" (Hasil dari Firebase)
                      if (_searchQuery.length >= 2) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text("GLOBAL SEARCH", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                        ),

                        // Tampilkan Loading jika sedang mencari
                        if (_isSearchingGlobal)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          )
                        // Tampilkan hasil jika data ditemukan
                        else if (_globalSearchResults.isNotEmpty)
                          ..._globalSearchResults.map((res) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: UIUtils.getAvatarColor(res['pubkey'] ?? ''),
                              child: Text(
                                UIUtils.getInitials(res['username'] ?? '?'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(res['username'] ?? ''),
                            subtitle: Text('${res['pubkey']?.substring(0, 16)}...',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),

                            // SEBELAH KANAN: Jadi Button terpisah
                            trailing: IconButton(
                              icon: Icon(Remix.user_add_line, color: Theme.of(context).iconTheme.color),
                              onPressed: () {
                                // Klik logonya baru beneran Add
                                _quickAddFromGlobal(res['username']!, res['pubkey']!);
                              },
                            ),

                            // AREA UTAMA: Klik masuk ke RoomChat (Tanpa Add)
                            onTap: () {
                              _searchFocusNode.unfocus();

                              final tempContact = Contact(
                                pubkey: res['pubkey']!,
                                name: res['username']!,
                                isSaved: false,
                                lastChatTime: 0,
                                lastMessage: '',
                                unreadCount: 0,
                              );

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ChatDetailScreen(
                                    contact: tempContact,
                                    relayManager: widget.relayManager,
                                  ),
                                ),
                              );
                            },
                          ))
                        // Tampilkan pesan jika tidak ada hasil
                        else if (!_isSearchingGlobal && _globalSearchResults.isEmpty && _searchQuery.length > 1)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text("No global user found", style: TextStyle(color: Colors.grey, fontSize: 13)),
                            )
                          else
                            const SizedBox.shrink(),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(height: 1, thickness: 0.1),
                        ),
                      ],

                      // SEKSI DAFTAR KONTAK SAYA
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text("MY CONTACTS", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.2)),
                      ),
                      ...contacts.map((contact) => _buildContactTile(contact)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: Material(
          color: Colors.grey.withAlpha(50),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: _addContact,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: const Icon(
                Remix.user_add_fill,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Widget tile kontak
  Widget _buildContactTile(Contact contact) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: UIUtils.getAvatarColor(contact.pubkey),
        child: Text(
          UIUtils.getInitials(contact.name),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(contact.name),
      subtitle: Text(
        '${contact.pubkey.substring(0, 16)}...',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
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
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _deleteContact(contact);
      },
    );
  }

  // Widget state kosong
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Remix.contacts_line, size: 80, color: Colors.grey.withAlpha(50)),
          const SizedBox(height: 20),
          const Text('No saved contacts yet', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}