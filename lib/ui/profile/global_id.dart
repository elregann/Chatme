// global_id.dart

import '../../widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../core/utils/bio_text.dart';
import '../../services/app_settings.dart';
import '../../services/chatme_toast.dart';
import '../../services/directory_service.dart';
import '../../relay_manager.dart';
import '../../widgets/chatme_notice.dart';

class GlobalIdPage extends StatefulWidget {
  final RelayManager? relayManager;
  const GlobalIdPage({super.key, this.relayManager});

  @override
  State<GlobalIdPage> createState() => _GlobalIdPageState();
}

class _GlobalIdPageState extends State<GlobalIdPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final FocusNode _bioFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isSavingBio = false;
  bool _isRemovingBio = false;

  /// True while the bio button should offer to remove an existing bio.
  ///
  /// Removal is destructive, so it is only offered when the page is idle:
  /// a bio is stored, the field is not focused, and the field still holds
  /// exactly that bio. Any edit or focus keeps the neutral Save button, which
  /// means a pending edit can never be thrown away by a stray tap.
  bool _showRemoveBio = false;

  @override
  void initState() {
    super.initState();
    final current = AppSettings.instance.myNip05;
    if (current.isNotEmpty) {
      _controller.text = current.split('@')[0];
    }
    _bioController.text = AppSettings.instance.myAbout;
    _bioController.addListener(_syncBioButton);
    _bioFocusNode.addListener(_syncBioButton);
    _showRemoveBio = _computeShowRemoveBio();
  }

  @override
  void dispose() {
    _bioController.removeListener(_syncBioButton);
    _bioFocusNode.removeListener(_syncBioButton);
    _controller.dispose();
    _bioController.dispose();
    _bioFocusNode.dispose();
    super.dispose();
  }

  bool _computeShowRemoveBio() {
    final saved = AppSettings.instance.myAbout;
    if (saved.isEmpty || _bioFocusNode.hasFocus) return false;
    final current = BioText.sanitize(
      _bioController.text,
      maxLength: BioText.maxUserLength,
    );
    return current == saved;
  }

  /// Rebuilds only when the button actually changes between Save and Remove,
  /// not on every keystroke.
  void _syncBioButton() {
    final next = _computeShowRemoveBio();
    if (next == _showRemoveBio) return;
    setState(() => _showRemoveBio = next);
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = ChatmeColors.backgroundPrimary;
    const cardColor = ChatmeColors.surfaceMenu;
    const borderColor = ChatmeColors.borderSubtle;
    const textSecondary = ChatmeColors.textSecondary;
    const textPrimary = ChatmeColors.textPrimary;

    final currentHandle = AppSettings.instance.myNip05;
    final hasHandle = currentHandle.isNotEmpty;

    // The bio button flips between the neutral Save state and the red Remove
    // state. Both share one layout so the page does not jump.
    final removeBio = _showRemoveBio;
    final bioBusy = _isSavingBio || _isRemovingBio;
    final bioForeground = removeBio
        ? ChatmeButtonStyles.dangerForeground
        : ChatmeButtonStyles.neutralForeground;
    final String bioLabel;
    if (_isRemovingBio) {
      bioLabel = 'Removing...';
    } else if (_isSavingBio) {
      bioLabel = 'Saving...';
    } else {
      bioLabel = removeBio ? 'Remove bio' : 'Save bio';
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Global ID',
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ChatmeNotice(
              icon: Icons.info_outline_rounded,
              message:
                  'Claim a unique username to make it easier for others to find you.',
            ),

            const SizedBox(height: 28),

            // Current handle display
            if (hasHandle) ...[
              const Text(
                'CURRENT ID',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.2,
                    color: textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Text(
                  currentHandle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Username input
            Text(
              hasHandle ? 'CHANGE TO' : 'CLAIM USERNAME',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 14, color: textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'username',
                        hintStyle:
                            TextStyle(fontSize: 14, color: textSecondary),
                        contentPadding:
                            EdgeInsets.fromLTRB(16, 14, 8, 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Text('@chatme',
                        style: TextStyle(fontSize: 13, color: textSecondary)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Claim / Update button
            GestureDetector(
              onTap: _isLoading
                  ? null
                  : () async {
                      final input = _controller.text
                          .trim()
                          .toLowerCase()
                          .replaceAll(RegExp(r'[^a-z0-9_]'), '');
                      if (input.length < 3) {
                        ChatmeToast.show(
                            'Username must be at least 3 characters');
                        return;
                      }

                      setState(() => _isLoading = true);

                      final result = await DirectoryService.claim(input);
                      final success = result == DirectoryResult.ok;

                      if (!mounted) return;
                      setState(() => _isLoading = false);

                      if (success) {
                        await AppSettings.instance
                            .updateNip05('$input@chatme', true);
                        try {
                          await widget.relayManager?.broadcastProfileKind0();
                        } catch (_) {}
                        if (!mounted) return;
                        setState(() {});
                        ChatmeToast.show('$input@chatme claimed');
                      } else {
                        ChatmeToast.show(result == DirectoryResult.taken
                            ? 'Username already taken'
                            : 'Could not reach the server, try again');
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
                      ),
                    if (_isLoading) const SizedBox(width: 8),
                    Text(
                      _isLoading
                          ? 'Claiming...'
                          : (hasHandle ? 'Update ID' : 'Claim ID'),
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

            if (hasHandle) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _isLoading ? null : _showDisconnectDialog,
                child: Container(
                  width: double.infinity,
                  padding: ChatmeButtonStyles.padding,
                  decoration: ChatmeButtonStyles.dangerDecoration(),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.link_off_rounded,
                        size: 16,
                        color: ChatmeButtonStyles.dangerForeground,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Disconnect ID',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ChatmeButtonStyles.dangerForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Bio editor. It lives in the kind 0 profile, not in the Chatme
            // directory, so it is available with or without a claimed ID.
            const Text(
              'BIO',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              child: TextField(
                controller: _bioController,
                focusNode: _bioFocusNode,
                style: const TextStyle(fontSize: 14, color: textPrimary),
                minLines: 3,
                maxLines: 5,
                maxLength: BioText.maxUserLength,
                textCapitalization: TextCapitalization.sentences,
                buildCounter: (context,
                    {required int currentLength,
                    required bool isFocused,
                    required int? maxLength}) {
                  final limit = maxLength ?? BioText.maxUserLength;
                  return Text(
                    '$currentLength/$limit',
                    style: TextStyle(
                      fontSize: 11,
                      color: currentLength >= limit
                          ? ChatmeColors.statusWarning
                          : textSecondary,
                    ),
                  );
                },
                decoration: const InputDecoration(
                  hintText: 'Tell people a little about yourself',
                  hintStyle:
                      TextStyle(fontSize: 14, color: textSecondary),
                  filled: false,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.public_rounded,
                      size: 13, color: textSecondary),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your bio is public and stored on Nostr relays.',
                    style: TextStyle(fontSize: 11, color: textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: bioBusy ? null : (removeBio ? _removeBio : _saveBio),
              child: Container(
                width: double.infinity,
                padding: ChatmeButtonStyles.padding,
                decoration: removeBio
                    ? ChatmeButtonStyles.dangerDecoration()
                    : ChatmeButtonStyles.neutralDecoration(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (bioBusy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: bioForeground,
                        ),
                      )
                    else if (removeBio)
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: bioForeground,
                      ),
                    if (bioBusy || removeBio) const SizedBox(width: 8),
                    Text(
                      bioLabel,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: bioForeground,
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
    );
  }

  Future<void> _saveBio() async {
    final settings = AppSettings.instance;
    final cleaned =
        BioText.sanitize(_bioController.text, maxLength: BioText.maxUserLength);

    if (cleaned == settings.myAbout) {
      // Keep the field honest when sanitizing removed characters, but do not
      // republish an unchanged profile.
      if (_bioController.text != cleaned) {
        _bioController.text = cleaned;
      }
      return;
    }

    setState(() => _isSavingBio = true);
    try {
      await settings.setMyAbout(cleaned);
      try {
        await widget.relayManager?.broadcastProfileKind0();
      } catch (_) {}

      if (!mounted) return;
      _bioController.text = cleaned;
      // Drop focus so a saved bio settles back into the idle state, where the
      // button offers to remove it.
      _bioFocusNode.unfocus();
      setState(() {
        _isSavingBio = false;
        _showRemoveBio = _computeShowRemoveBio();
      });
      ChatmeToast.show('Bio saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingBio = false);
      ChatmeToast.show('Could not save the bio: $e');
    }
  }

  /// Clears the bio and republishes kind 0 without an `about` field.
  ///
  /// Deliberately silent: no confirmation dialog and no snackbar. The button
  /// itself is the whole action, and it returns to the neutral Save state.
  Future<void> _removeBio() async {
    if (_isSavingBio || _isRemovingBio) return;

    setState(() => _isRemovingBio = true);
    try {
      await AppSettings.instance.setMyAbout('');
      try {
        await widget.relayManager?.broadcastProfileKind0();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isRemovingBio = false;
        _showRemoveBio = false;
      });
      _bioController.clear();
      _bioFocusNode.unfocus();
    } catch (_) {
      // Keep the bio and the field as they are; only stop the spinner.
      if (!mounted) return;
      setState(() {
        _isRemovingBio = false;
        _showRemoveBio = _computeShowRemoveBio();
      });
    }
  }

  Future<void> _showDisconnectDialog() async {
    final currentHandle = AppSettings.instance.myNip05;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Disconnect ID?',
      message:
          'Your unique username $currentHandle will be released and removed from your profile. This action cannot be undone.',
      confirmLabel: 'Disconnect',
    );

    if (confirmed && mounted) {
      setState(() => _isLoading = true);
      try {
        if (AppSettings.instance.myNip05.isNotEmpty) {
          await DirectoryService.release();
        }

        await AppSettings.instance.updateNip05('', false);
        try {
          await widget.relayManager?.broadcastProfileKind0();
        } catch (_) {}

        // The identity was just released — clear it from our own contact
        // row too so the chat list immediately falls back to npub.
        await AppSettings.clearContactIdentity(AppSettings.instance.myPubkey);

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _controller.clear();
        });

        ChatmeToast.show('Global ID disconnected');
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ChatmeToast.show('Failed to disconnect: $e');
      }
    }
  }
}
