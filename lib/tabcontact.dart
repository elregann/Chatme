import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'main.dart';
import 'roomchat.dart';
import 'relaymanager.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ContactsScreen extends StatefulWidget {
  final RelayManager relayManager;
  const ContactsScreen({super.key, required this.relayManager});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  bool _isResolving = false;

  // Ganti/Tambah kode di atas void _addContact()
  Future<String?> _resolveNip05(String nip05) async {
    try {
      if (!nip05.contains('@')) return null;

      final parts = nip05.split('@');
      final name = parts[0];
      final domain = parts[1];

      // Request dengan Header lengkap agar tidak kena status 418 (Teapot)
      final url = Uri.parse('https://$domain/.well-known/nostr.json?name=$name');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0', // Pura-pura jadi browser
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Cek dulu apakah field 'names' ada, jangan langsung tembak
        if (data != null && data['names'] != null && data['names'][name] != null) {
          return data['names'][name] as String;
        }
      } else {
        DebugLogger.log('📡 Server Error ${response.statusCode}: ${response.body}', type: 'NETWORK');
      }
    } catch (e) {
      DebugLogger.log('❌ NIP-05 Resolve Error: $e', type: 'ERROR');
    }
    return null;
  }

  // Tambah kontak baru
  Future<void> _addContact() async {
    final nameController = TextEditingController();
    final pubkeyController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header ala ProfileScreen
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_add_rounded, color: Colors.blue, size: 28),
              ),
              const SizedBox(height: 12),
              const Text('Add Contact', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 6),
              Text(
                'Add a new friend via Nostr Public Key.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(180)),
              ),

              // Indikator Loading di dalam Dialog
              if (_isResolving)
                const Padding(
                  padding: EdgeInsets.only(top: 12.0),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)
                  ),
                ),

              const SizedBox(height: 20),

              Form(
                key: formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter name...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.withAlpha(150)),
                        filled: true,
                        fillColor: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(10),
                        prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? 'Name required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: pubkeyController,
                      maxLines: 2,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Paste Public Key here...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.withAlpha(150), fontFamily: 'sans-serif'),
                        filled: true,
                        fillColor: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(10),
                        prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.content_paste_rounded, size: 18),
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) pubkeyController.text = data!.text!.trim();
                            HapticFeedback.lightImpact();
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Public Key or NIP-05 required';
                        if (!value.contains('@') && value.length != 64) return 'Must be 64 characters or NIP-05';
                        return null;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isResolving ? null : () async {
                        if (formKey.currentState!.validate()) {
                          final name = nameController.text.trim();
                          String targetPubkey = pubkeyController.text.trim().toLowerCase();

                          if (targetPubkey.contains('@')) {
                            setDialogState(() => _isResolving = true);

                            final resolvedHex = await _resolveNip05(targetPubkey);

                            if (context.mounted) {
                              setDialogState(() => _isResolving = false);
                            }

                            if (resolvedHex == null) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('❌ NIP-05 not found'), backgroundColor: Colors.red),
                                );
                              }
                              return;
                            }
                            targetPubkey = resolvedHex;
                          }

                          try {
                            final contactsBox = Hive.box<Contact>('contacts');
                            final existingContact = contactsBox.get(targetPubkey);

                            final contact = Contact(
                              pubkey: targetPubkey,
                              name: name,
                              isSaved: true,
                              lastChatTime: existingContact?.lastChatTime ?? 0,
                              lastMessage: existingContact?.lastMessage ?? '',
                              unreadCount: existingContact?.unreadCount ?? 0,
                            );

                            await contactsBox.put(targetPubkey, contact);
                            HapticFeedback.mediumImpact();
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            DebugLogger.log('❌ Error: $e', type: 'ERROR');
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(_isResolving ? 'Searching...' : 'Add Contact', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
            // Header Ikon Peringatan (Style Profile)
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
      DebugLogger.log('👤 Contact removed from list: ${contact.name}', type: 'UI');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
      ),
      body: ValueListenableBuilder<Box<Contact>>(
        valueListenable: Hive.box<Contact>('contacts').listenable(),
        builder: (context, box, _) {
          final contacts = box.values
              .where((c) => c.isSaved == true)
              .toList();

          contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

          if (contacts.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return _buildContactTile(contact);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        backgroundColor: Colors.blue.withAlpha(40),
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
        child: const Icon(Icons.person_add, color: Colors.blue),
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