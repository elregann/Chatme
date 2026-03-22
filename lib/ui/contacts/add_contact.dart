import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/contact.dart';
import '../../core/utils/debug_logger.dart';

class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pubkeyController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _pubkeyController.dispose();
    super.dispose();
  }

  void _resetSubmitted() {
    if (_submitted) setState(() => _submitted = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final textPrimary = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Add contact',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.withAlpha(30), width: 0.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.blue.withAlpha(200), size: 14),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add a new friend using their Nostr public key.',
                        style: TextStyle(fontSize: 13, color: Colors.blue.withAlpha(200), height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Name field
              Text(
                'NAME',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: TextStyle(fontSize: 14, color: textPrimary),
                onTap: _resetSubmitted,
                onChanged: (_) => _resetSubmitted(),
                decoration: InputDecoration(
                  hintText: 'Enter name',
                  hintStyle: TextStyle(fontSize: 13, color: textSecondary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  errorStyle: const TextStyle(fontSize: 11, height: 1.2),
                ),
                validator: (value) {
                  if (!_submitted) return null;
                  if (value == null || value.isEmpty) return 'Name is required';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Pubkey field
              Text(
                'PUBLIC KEY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pubkeyController,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                onTap: _resetSubmitted,
                onChanged: (_) => _resetSubmitted(),
                decoration: InputDecoration(
                  hintText: 'Paste public key here',
                  hintStyle: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 14, bottom: 14),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor, width: 0.5)),
                  errorStyle: const TextStyle(fontSize: 11, height: 1.2),
                  suffixIcon: GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _pubkeyController.text = data!.text!.trim();
                        HapticFeedback.lightImpact();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.content_paste_rounded, size: 18, color: textSecondary),
                    ),
                  ),
                ),
                validator: (value) {
                  if (!_submitted) return null;
                  if (value == null || value.isEmpty) return 'Public key is required';
                  if (value.trim().length != 64) return 'Must be 64 characters';
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // Add button
              GestureDetector(
                onTap: _isLoading ? null : () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  setState(() => _submitted = true);
                  await Future.microtask(() {});
                  if (!_formKey.currentState!.validate()) return;

                  setState(() => _isLoading = true);

                  try {
                    final name = _nameController.text.trim();
                    final pubkey = _pubkeyController.text.trim().toLowerCase();

                    final contactsBox = Hive.box<Contact>('contacts');
                    final existing = contactsBox.get(pubkey);

                    final contact = Contact(
                      pubkey: pubkey,
                      name: name,
                      isSaved: true,
                      lastChatTime: existing?.lastChatTime ?? 0,
                      lastMessage: existing?.lastMessage ?? '',
                      unreadCount: existing?.unreadCount ?? 0,
                    );

                    await contactsBox.put(pubkey, contact);
                    HapticFeedback.mediumImpact();
                    navigator.pop(true);
                  } catch (e) {
                    DebugLogger.log('❌ Error: $e', type: 'ERROR');
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Failed to add contact', style: TextStyle(color: Colors.white)),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoading)
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: textPrimary))
                      else
                        Icon(Icons.person_add_alt_1_rounded, size: 16, color: textPrimary),
                      const SizedBox(width: 8),
                      Text(
                        _isLoading ? 'Adding...' : 'Add contact',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}