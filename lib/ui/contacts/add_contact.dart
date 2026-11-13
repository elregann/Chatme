// add_contact.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remixicon/remixicon.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/contact.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../core/utils/debug_logger.dart';
import '../../core/utils/key_utils.dart';
import '../../core/utils/shortcut_helper.dart';
import '../../widgets/chatme_notice.dart';

class AddContactPage extends StatefulWidget {
  /// Public key (hex) to fill in, for example from a scanned QR code.
  final String? initialPubkey;

  const AddContactPage({super.key, this.initialPubkey});

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
  void initState() {
    super.initState();
    final initial = widget.initialPubkey;
    if (initial != null) _pubkeyController.text = KeyUtils.toNpub(initial);
  }

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
    const bgColor = ChatmeColors.backgroundPrimary;
    const cardColor = ChatmeColors.surfaceMenu;
    const borderColor = ChatmeColors.borderSubtle;
    const textSecondary = ChatmeColors.textSecondary;
    const textPrimary = ChatmeColors.textPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Add contact',
          style: TextStyle(
              fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: textPrimary, size: 18),
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
              const ChatmeNotice(
                icon: Icons.info_outline_rounded,
                message:
                    'Add a new friend using their Nostr public key, npub or nprofile.',
              ),

              const SizedBox(height: 28),

              // Name field
              const Text(
                'NAME',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: textSecondary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                autofocus: widget.initialPubkey != null,
                style: const TextStyle(fontSize: 14, color: textPrimary),
                onTap: _resetSubmitted,
                onChanged: (_) => _resetSubmitted(),
                decoration: InputDecoration(
                  hintText: 'Enter name',
                  hintStyle:
                      const TextStyle(fontSize: 13, color: textSecondary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
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
              const Text(
                'NPUB, NPROFILE, PUBKEY',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: textSecondary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pubkeyController,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                onTap: _resetSubmitted,
                onChanged: (_) => _resetSubmitted(),
                decoration: InputDecoration(
                  hintText: 'Paste here',
                  hintStyle: const TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.only(
                      left: 16, right: 8, top: 14, bottom: 14),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: borderColor, width: 0.5)),
                  errorStyle: const TextStyle(fontSize: 11, height: 1.2),
                  suffixIcon: GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _pubkeyController.text = data!.text!.trim();
                        HapticFeedback.lightImpact();
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.content_paste_rounded,
                          size: 18, color: textSecondary),
                    ),
                  ),
                ),
                validator: (value) {
                  if (!_submitted) return null;
                  if (value == null || value.isEmpty) {
                    return 'Public key is required';
                  }
                  final normalized = KeyUtils.normalizeToHex(value);
                  if (normalized.length != 64) {
                    return 'Must be 64-character hex, a valid npub or nprofile';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),

              // Add button
              GestureDetector(
                onTap: _isLoading
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);

                        setState(() => _submitted = true);
                        await Future.microtask(() {});
                        if (!_formKey.currentState!.validate()) return;

                        setState(() => _isLoading = true);

                        try {
                          final name = _nameController.text.trim();
                          final pubkeyInput = _pubkeyController.text.trim();
                          final pubkey = KeyUtils.normalizeToHex(pubkeyInput);

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

                          await ShortcutHelper.pushConversationShortcut(
                            id: pubkey,
                            name: contact.displayName,
                            avatarBytes: null,
                          );

                          HapticFeedback.mediumImpact();
                          navigator.pop(true);
                        } catch (e) {
                          DebugLogger.log('❌ Error: $e', type: 'ERROR');
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Failed to add contact',
                                style:
                                    TextStyle(color: ChatmeColors.textPrimary),
                              ),
                              backgroundColor: ChatmeColors.statusDanger,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: ChatmeButtonStyles.padding,
                  decoration: ChatmeButtonStyles.primaryDecoration(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: ChatmeButtonStyles.primaryForeground,
                          ),
                        )
                      else
                        const Icon(
                          Remix.user_add_fill,
                          size: 16,
                          color: ChatmeButtonStyles.primaryForeground,
                        ),
                      const SizedBox(width: 8),
                      Text(
                        _isLoading ? 'Adding...' : 'Add contact',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ChatmeButtonStyles.primaryForeground,
                        ),
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
