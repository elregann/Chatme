// tab_profile.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'relay_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/account_logout.dart';
import 'services/app_settings.dart';
import 'services/link_preview_service.dart';
import 'core/utils/key_utils.dart';
import 'ui/profile/security_vault.dart';
import 'ui/profile/recovery_phrase.dart';
import 'core/theme/chatme_buttons.dart';
import 'core/theme/chatme_colors.dart';
import 'ui/profile/global_id.dart';
import 'ui/profile/relay_status.dart';
import 'ui/profile/file_servers.dart';
import 'ui/profile/key_converter.dart';
import 'ui/profile/privacy_policy_page.dart';
import 'ui/qr/qr_code_page.dart';
import 'widgets/profile_bio.dart';
import 'ui/chat_image_crop_page.dart';
import 'package:remixicon/remixicon.dart';
import 'dart:io' show File, Platform;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'widgets/user_avatar.dart';
import 'widgets/profile_photo_viewer.dart';
import 'widgets/chatme_menu.dart';
import 'widgets/confirm_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final RelayManager relayManager;

  /// Called after local data is wiped and the new account is ready, so the
  /// shell can jump back to the Chats tab.
  final VoidCallback? onResetComplete;

  const ProfileScreen({
    super.key,
    required this.relayManager,
    this.onResetComplete,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nip05Controller = TextEditingController();
  bool _isEditing = true;
  String _currentHandle = "";
  String? _localPhotoPath;
  String? _remotePhotoUrl;
  String _appVersion = "";
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();

    _currentHandle = AppSettings.instance.myNip05;
    _localPhotoPath = _hasUsablePhotoFile(AppSettings.instance.myPhotoPath)
        ? AppSettings.instance.myPhotoPath
        : null;
    _remotePhotoUrl = AppSettings.instance.myPhotoUrl.isNotEmpty
        ? AppSettings.instance.myPhotoUrl
        : null;
    if (_currentHandle.isNotEmpty) {
      _isEditing = false;
      _nip05Controller.text = _currentHandle.split('@')[0];
    }
    _loadAppVersion();
  }

  // The version comes from the built app, which follows pubspec.yaml, so the
  // Me page never needs a manual version bump again.
  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = info.version);
  }

  @override
  void dispose() {
    _nip05Controller.dispose();
    super.dispose();
  }

  void _openMyPhotoPreview() {
    final settings = AppSettings.instance;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePhotoViewer(
          pubkey: settings.myPubkey,
          name: settings.myName.isNotEmpty
              ? settings.myName
              : (_currentHandle.isNotEmpty ? _currentHandle : null),
          localPhotoPath: _hasUsablePhotoFile(_localPhotoPath)
              ? _localPhotoPath
              : (_hasUsablePhotoFile(settings.myPhotoPath)
                  ? settings.myPhotoPath
                  : null),
          photoUrl: _remotePhotoUrl ?? settings.myPhotoUrl,
          relayManager: widget.relayManager,
        ),
      ),
    );
  }

  Future<void> _pickPhoto() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: ChatmeColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        const borderColor = ChatmeColors.borderSubtle;
        const textPrimary = ChatmeColors.textPrimary;
        const textSecondary = ChatmeColors.textSecondary;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile photo',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose a source',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 16),
              const Divider(height: 0.5, thickness: 0.5, color: borderColor),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _processImage(ImageSource.camera, widget.relayManager);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt_outlined,
                          size: 18, color: textPrimary),
                      SizedBox(width: 8),
                      Text('Take a photo',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textPrimary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  await _processImage(ImageSource.gallery, widget.relayManager);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 18, color: textPrimary),
                      SizedBox(width: 8),
                      Text('Choose from gallery',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textPrimary)),
                    ],
                  ),
                ),
              ),
              if (_localPhotoPath != null || _remotePhotoUrl != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _localPhotoPath = null;
                      _remotePhotoUrl = null;
                    });
                    AppSettings.instance.savePhotoPath('');
                    AppSettings.instance.savePhotoUrl('');
                    // Broadcast to the relay that the photo has been deleted
                    widget.relayManager
                        .broadcastProfileKind0(removePhoto: true);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: ChatmeButtonStyles.dangerDecoration(),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: ChatmeButtonStyles.dangerForeground,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Remove photo',
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
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processImage(
      ImageSource source, RelayManager relayManager) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );
    if (picked == null) return;

    if (!mounted) return;

    final imageBytes = await picked.readAsBytes();
    if (imageBytes.isEmpty || !mounted) return;

    // Crop in the same page the chat image sender uses, locked to 1:1.
    final croppedBytes = await ChatImageCropPage.open(
      context,
      imageBytes,
      aspectRatio: 1,
    );
    if (croppedBytes == null || croppedBytes.isEmpty || !mounted) return;

    // Saving and uploading a photo is not supported on web.
    if (kIsWeb) return;

    final directory = await getTemporaryDirectory();
    final croppedFile = File(
      '${directory.path}${Platform.pathSeparator}'
      'profile_photo_${DateTime.now().millisecondsSinceEpoch}'
      '${_photoFileExtension(croppedBytes)}',
    );
    await croppedFile.writeAsBytes(croppedBytes, flush: true);

    if (mounted) {
      setState(() => _localPhotoPath = croppedFile.path);
      await AppSettings.instance.savePhotoPath(croppedFile.path);

      // Upload dan broadcast ke relay
      final url =
          await widget.relayManager.uploadPhotoToNostrBuild(croppedFile.path);
      if (url != null) {
        await widget.relayManager.broadcastProfileKind0(photoUrl: url);
        await AppSettings.instance.savePhotoUrl(url);

        // Preload the permanent URL before dropping the local file, so the
        // avatar moves straight from the new local photo to the new remote
        // photo without showing the previous remote photo in between.
        if (mounted) {
          final provider = CachedNetworkImageProvider(url);
          var failed = false;
          try {
            await precacheImage(
              provider,
              context,
              onError: (_, __) => failed = true,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () => failed = true,
            );
          } catch (_) {
            failed = true;
          }
          if (!failed && mounted) {
            UserAvatar.setResolvedProvider(
              AppSettings.instance.myPubkey,
              url,
              provider,
            );
          }
        }

        // The URL is now the permanent source. Drop the temporary local
        // copy so a later launch never renders a file that may be gone.
        await AppSettings.instance.savePhotoPath('');
        if (mounted) {
          setState(() {
            _remotePhotoUrl = url;
            _localPhotoPath = null;
          });
        }
        await _deleteTempPhoto(croppedFile);
      }
    }
  }

  Future<void> _deleteTempPhoto(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The OS may already have cleaned the temporary directory.
    }
  }

  bool _hasUsablePhotoFile(String? path) {
    if (kIsWeb || path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }

  /// The file extension that matches the bytes of a cropped image.
  String _photoFileExtension(Uint8List bytes) {
    const pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length >= pngHeader.length) {
      for (var i = 0; i < pngHeader.length; i++) {
        if (bytes[i] != pngHeader[i]) return '.jpg';
      }
      return '.png';
    }
    return '.jpg';
  }

  Color _getAvatarColor(String pubkey) {
    if (pubkey.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);
    } catch (e) {
      return ChatmeColors.accentDeep;
    }
  }

  // Widget title section - Updated color to textSecondary
  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            color: color),
      ),
    );
  }

  // Widget step guide
  Widget _buildGuideStep(
      BuildContext context, int step, String text, Color textStyleColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: Colors.grey.withAlpha(50),
            child: Text(
              step.toString(),
              style: TextStyle(
                fontSize: 10,
                color: textStyleColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: textStyleColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showBackupDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BackupKeysPage(
          pubkey: AppSettings.instance.myPubkey,
          privkey: AppSettings.instance.myPrivkey,
          exportKeys: AppSettings.instance.exportKeys,
        ),
      ),
    );
  }

  void _showMnemonicDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecoveryPhrasePage()),
    );
  }

  Future<void> _openGlobalId() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GlobalIdPage(relayManager: widget.relayManager),
      ),
    );
    if (!mounted) return;
    setState(() {
      _currentHandle = AppSettings.instance.myNip05;
      _isEditing = _currentHandle.isEmpty;
    });
  }

  /// Signs out of the local account after an explicit confirmation. The old
  /// account itself is not touched: only this device's data is erased, then
  /// the user returns to the Welcome screen to create or restore an account.
  Future<void> _confirmLogout() async {
    if (_isLoggingOut) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Log out?',
      message:
          'All chats, contacts and settings on this device will be erased and you will return to the login screen. Your old account and its profile stay online and can be restored with your backup phrase or nsec.',
      confirmLabel: 'Log out',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLoggingOut = true);
    try {
      await AccountLogout.signOut(widget.relayManager);
      if (!mounted) return;

      setState(() {
        _currentHandle = '';
        _isEditing = true;
        _nip05Controller.clear();
        _localPhotoPath = null;
        _remotePhotoUrl = null;
        _isLoggingOut = false;
      });
      widget.onResetComplete?.call();
    } catch (e) {
      debugPrint('[Profile] Logout failed | $e');
      if (!mounted) return;
      setState(() => _isLoggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not sign out: $e')),
      );
    }
  }

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild only when a setting this screen actually reads changes, e.g.
    // after a restore or when the relay delivers our own kind-0 event.
    // Listening to the whole settings box made every unrelated write, such
    // as keyboard height or cut-off timestamps, rebuild the Profile tab.
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(
        keys: const [
          'my_pubkey',
          'my_nip05',
          'my_about',
          'my_photo_path',
          'my_photo_url',
          'link_previews_enabled',
          'read_receipts_enabled',
          'save_to_gallery',
        ],
      ),
      builder: (context, _, __) {
        final settings = AppSettings.instance;

        const bgColor = ChatmeColors.backgroundPrimary;
        const cardColor = ChatmeColors.surfaceMenu;
        const borderColor = ChatmeColors.borderSubtle;
        const textPrimary = ChatmeColors.textPrimary;
        const textSecondary = ChatmeColors.textSecondary;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            centerTitle: false,
            leading: IconButton(
              icon: const Icon(Icons.qr_code_2_rounded,
                  color: textPrimary, size: 26),
              tooltip: 'My QR code',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrCodePage(
                    pubkey: settings.myPubkey,
                    name: settings.myName,
                    relayManager: widget.relayManager,
                  ),
                ),
              ),
            ),
            elevation: 0,
            actions: [
              ChatmeMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: textPrimary),
                entries: _isLoggingOut
                    ? const <ChatmeMenuEntry<String>>[]
                    : const [
                        ChatmeMenuEntry<String>(
                          value: 'logout',
                          icon: Icons.logout,
                          label: 'Log out',
                        ),
                      ],
                onSelected: (value) {
                  if (value == 'logout') _confirmLogout();
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _openMyPhotoPreview,
                        child: Stack(
                          children: [
                            _hasUsablePhotoFile(_localPhotoPath)
                                ? CircleAvatar(
                                    radius: 40,
                                    backgroundColor:
                                        _getAvatarColor(settings.myPubkey),
                                    backgroundImage:
                                        FileImage(File(_localPhotoPath!)),
                                  )
                                : _hasUsablePhotoFile(settings.myPhotoPath)
                                    ? CircleAvatar(
                                        radius: 40,
                                        backgroundColor:
                                            _getAvatarColor(settings.myPubkey),
                                        backgroundImage: FileImage(
                                            File(settings.myPhotoPath)),
                                      )
                                    : UserAvatar(
                                        pubkey: settings.myPubkey,
                                        name: settings.myName.isNotEmpty
                                            ? settings.myName
                                            : (_currentHandle.isNotEmpty
                                                ? _currentHandle
                                                : null),
                                        radius: 40,
                                        relayManager: widget.relayManager,
                                      ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: _pickPhoto,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: ChatmeColors.accentPrimary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: ChatmeColors.backgroundPrimary,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(Icons.edit_rounded,
                                      size: 12, color: ChatmeColors.onAccent),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                          (!_isEditing && _currentHandle.isNotEmpty)
                              ? _currentHandle.split('@')[0]
                              : settings.myName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textPrimary)),
                      const SizedBox(height: 6),
                      // The bio sits under the name without a card. A long
                      // bio is clipped to a few lines and opens in a sheet,
                      // so it cannot push the rest of the page away.
                      ProfileBioText(
                        about: settings.myAbout,
                        maxLines: 3,
                        textAlign: TextAlign.center,
                        showEmptyHint: true,
                        emptyHint: 'Add a bio',
                        onEmptyTap: _openGlobalId,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Global ID', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor, width: 0.5),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    title: Text(
                      AppSettings.instance.myNip05.isNotEmpty
                          ? AppSettings.instance.myNip05
                          : 'Claim your ID',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textPrimary),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: textSecondary),
                    onTap: _openGlobalId,
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Your Npub', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: borderColor, width: 0.5)),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: SelectableText(
                      KeyUtils.toNpub(settings.myPubkey),
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: textSecondary),
                    ),
                    trailing: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: KeyUtils.toNpub(settings.myPubkey)));
                          HapticFeedback.lightImpact();
                        },
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: textSecondary.withAlpha(20),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.copy_rounded,
                              color: textSecondary, size: 18),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Tools', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor, width: 0.5),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.swap_horiz_rounded,
                        color: textPrimary, size: 18),
                    title: const Text('Key Converter',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: textSecondary),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const KeyConverterPage()),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Network', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Remix.server_fill,
                            color: textPrimary, size: 18),
                        title: const Text('Relays',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: textSecondary),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => RelayStatusPage(
                                  relayManager: widget.relayManager)),
                        ),
                      ),
                      const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                          indent: 56),
                      ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading: const Icon(Icons.cloud_upload_outlined,
                            color: textPrimary, size: 18),
                        title: const Text('File servers',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: textSecondary),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const FileServersPage()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Privacy', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.link_rounded,
                            color: textPrimary, size: 18),
                        title: const Text('Link previews',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        subtitle: const Text(
                          'Loads the linked site to show a preview. The site can see your IP address.',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                        value: settings.linkPreviewsEnabled,
                        onChanged: (value) async {
                          await settings.setLinkPreviewsEnabled(value);
                          if (!value) await LinkPreviewService.instance.clear();
                        },
                      ),
                      const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                          indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.done_all_rounded,
                            color: textPrimary, size: 18),
                        title: const Text('Read receipts',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        subtitle: const Text(
                          "When off, you won't send or see blue ticks.",
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                        value: settings.readReceiptsEnabled,
                        onChanged: (value) =>
                            settings.setReadReceiptsEnabled(value),
                      ),
                      const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                          indent: 56),
                      SwitchListTile(
                        secondary: const Icon(Icons.photo_library_outlined,
                            color: textPrimary, size: 18),
                        title: const Text('Save to Gallery',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        subtitle: const Text(
                          'Copies photos you receive to a Chatme album. Other apps with photo access can see them.',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                        value: settings.saveToGalleryEnabled,
                        onChanged: (value) =>
                            settings.setSaveToGalleryEnabled(value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Security & Account', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: borderColor, width: 0.5)),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Remix.eye_fill,
                            color: textPrimary, size: 18),
                        title: const Text('Recovery Phrase',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: textSecondary),
                        onTap: () => _showMnemonicDialog(context),
                      ),
                      const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                          indent: 56),
                      ListTile(
                        leading: const Icon(Remix.key_fill,
                            color: textPrimary, size: 18),
                        title: const Text('Security Vault',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: textSecondary),
                        onTap: () => _showBackupDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Information', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: borderColor, width: 0.5)),
                  child: Column(
                    children: [
                      ListTile(
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        leading: const Icon(Icons.privacy_tip_outlined,
                            color: textPrimary, size: 18),
                        title: const Text('Privacy Policy',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: textSecondary),
                        onTap: () => _openPrivacyPolicy(context),
                      ),
                      const Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: borderColor,
                          indent: 56),
                      ListTile(
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(12)),
                        ),
                        leading: const Icon(Icons.article_outlined,
                            color: textPrimary, size: 18),
                        title: const Text('Licenses',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textPrimary)),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: textSecondary),
                        onTap: () async {
                          final List<LicenseEntry> licenses =
                              await LicenseRegistry.licenses.toList();
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Scaffold(
                                backgroundColor: bgColor,
                                appBar: AppBar(
                                  backgroundColor: bgColor,
                                  elevation: 0,
                                  scrolledUnderElevation: 0,
                                  centerTitle: true,
                                  title: const Text('Licenses',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                          color: textPrimary)),
                                  leading: IconButton(
                                    icon: const Icon(
                                        Icons.arrow_back_ios_rounded,
                                        color: textPrimary,
                                        size: 18),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                                body: ListView.builder(
                                  padding: const EdgeInsets.all(24.0),
                                  itemCount: licenses.length,
                                  itemBuilder: (context, index) {
                                    final entry = licenses[index];
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(entry.packages.join(', '),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: textPrimary)),
                                        const SizedBox(height: 8),
                                        ...entry.paragraphs.map((p) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Text(p.text,
                                                  style: const TextStyle(
                                                      fontSize: 14,
                                                      height: 1.6,
                                                      color: textSecondary)),
                                            )),
                                        if (index < licenses.length - 1)
                                          const Divider(
                                              color: borderColor, height: 48),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('How to Chat', textSecondary),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: borderColor, width: 0.5)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildGuideStep(
                            context,
                            1,
                            'Set your handle in Global ID to be searchable',
                            textPrimary),
                        _buildGuideStep(
                            context,
                            2,
                            'Or copy your Npub to share privately',
                            textPrimary),
                        _buildGuideStep(
                            context,
                            3,
                            'Go to Contacts to search name or paste key',
                            textPrimary),
                        _buildGuideStep(
                            context,
                            4,
                            'Add them to your verified contact list',
                            textPrimary),
                        _buildGuideStep(
                            context,
                            5,
                            'Start chatting securely in Chats tab',
                            textPrimary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor, width: 0.5),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    leading: const Icon(Icons.info_outline_rounded,
                        color: textPrimary, size: 18),
                    title: const Text('Version',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary)),
                    trailing: Text(_appVersion,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textSecondary)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
