import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'main.dart';
import 'roomchat.dart';
import 'relaymanager.dart';

class ContactsScreen extends StatefulWidget {
  final RelayManager relayManager;
  const ContactsScreen({super.key, required this.relayManager});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  // Tambah kontak baru
  Future<void> _addContact() async {
    final nameController = TextEditingController();
    final pubkeyController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Contact'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => (value == null || value.isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: pubkeyController,
                decoration: const InputDecoration(labelText: 'Public Key'),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Enter a public key';
                  if (value.length != 64) return 'Must be 64 characters';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final name = nameController.text.trim();
                final pubkey = pubkeyController.text.trim().toLowerCase();
                try {
                  final contactsBox = Hive.box<Contact>('contacts');
                  final existingContact = contactsBox.get(pubkey);

                  final contact = Contact(
                    pubkey: pubkey,
                    name: name,
                    isSaved: true,
                    lastChatTime: existingContact?.lastChatTime ?? 0,
                    lastMessage: existingContact?.lastMessage ?? '',
                    unreadCount: existingContact?.unreadCount ?? 0,
                  );

                  await contactsBox.put(pubkey, contact);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  DebugLogger.log('❌ Error adding contact: $e', type: 'ERROR');
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Hapus kontak
  Future<void> _deleteContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove ${contact.name} from contacts? Chat history will remain.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
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
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _deleteContact(contact),
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
    );
  }

  // Widget state kosong
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.contacts_outlined, size: 80, color: Theme.of(context).disabledColor),
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