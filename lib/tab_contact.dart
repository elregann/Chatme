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
          SnackBar(content: Text('$name added to contacts'), backgroundColor: Colors.green),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_remove_rounded, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Remove Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),

            // Teks Penjelasan
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(180),
                    height: 1.5
                ),
                children: [
                  const TextSpan(text: 'Are you sure you want to remove '),
                  TextSpan(
                    text: contact.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const TextSpan(text: '?\n'),
                  const TextSpan(
                    text: 'Don\'t worry, chat history will remain.',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons (Style Restore)
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
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
                    child: const Text('Remove', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
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
          title: const Text('Contacts'),
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
                              backgroundColor: Colors.blue.withAlpha(30),
                              child: const Icon(Icons.public, color: Colors.blue, size: 20),
                            ),
                            title: Text(res['username'] ?? ''),
                            subtitle: Text('${res['pubkey']?.substring(0, 16)}...', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                            trailing: const Icon(Icons.person_add_alt_1_rounded, color: Colors.blue),
                            onTap: () {
                              _searchFocusNode.unfocus();
                              _quickAddFromGlobal(res['username']!, res['pubkey']!);
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
        floatingActionButton: FloatingActionButton(
          onPressed: _addContact,
          backgroundColor: Colors.blue.withAlpha(40),
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.blue),
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
          Icon(Icons.people, size: 80, color: Theme.of(context).disabledColor),
          const SizedBox(height: 20),
          const Text('No saved contacts yet'),
          const SizedBox(height: 20),
          FilledButton.tonal(
              style: FilledButton.styleFrom(elevation: 0),
              onPressed: _addContact,
              child: const Text('Add Contact')
          ),
        ],
      ),
    );
  }
}