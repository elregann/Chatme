// tab_profile.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'relay_manager.dart';
import 'package:flutter/foundation.dart';
import 'services/app_settings.dart';
import 'ui/profile/security_vault.dart';
import 'ui/profile/recovery_phrase.dart';
import 'ui/profile/restore_account.dart';
import 'ui/profile/appearance.dart';
import 'ui/profile/global_id.dart';
import 'ui/profile/relay_status.dart';
import 'ui/profile/key_converter.dart';
import 'package:remixicon/remixicon.dart';

class ProfileScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeToggle;
  final RelayManager relayManager;

  const ProfileScreen({
    super.key,
    required this.onThemeToggle,
    required this.relayManager,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nip05Controller = TextEditingController();
  bool _isEditing = true;
  String _currentHandle = "";

  @override
  void initState() {
    super.initState();

    _currentHandle = AppSettings.instance.myNip05;
    if (_currentHandle.isNotEmpty) {
      _isEditing = false;
      _nip05Controller.text = _currentHandle.split('@')[0];
    }
  }

  @override
  void dispose() {
    _nip05Controller.dispose();
    super.dispose();
  }

  Color _getAvatarColor(String pubkey) {
    if (pubkey.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(pubkey.substring(0, 8), radix: 16) | 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  // Widget title section - Updated color to textSecondary
  Widget _buildSectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: color),
      ),
    );
  }

  // Widget step guide
  Widget _buildGuideStep(BuildContext context, int step, String text, Color textStyleColor) {
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

  void _showRestoreDialog(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestoreAccountPage(relayManager: widget.relayManager),
      ),
    );

    if (mounted) {
      setState(() {
        _currentHandle = AppSettings.instance.myNip05;
        _isEditing = _currentHandle.isEmpty;
      });
    }
  }

  void _showThemeDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppearancePage(onThemeToggle: widget.onThemeToggle),
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context, Color bgColor, Color textPrimary, Color textSecondary) {
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
            title: Text(
              'Privacy Policy',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chatme is a decentralized communication tool built on the Nostr protocol, where privacy is inherent because we operate without central servers. Every message is locally secured with end-to-end encryption using your Private Key, ensuring that you alone own your data. However, this absolute sovereignty means account recovery is impossible if your keys are lost. While our ecosystem promotes transparency through open-source relays, please be aware that metadata such as your IP address may remain visible to the specific relay providers you connect to.\n\n'
                      'To safeguard your conversations, Chatme implements an encryption framework based on the NIP-04 standard. We utilize AES-256-CBC for message encryption and SHA-256/HMAC for integrity, leveraging the secp256k1 curve for key exchange. By cryptographically binding the identities of the sender and receiver to each encrypted packet, we ensure absolute message privacy and prevent unauthorized manipulation.\n\n'
                      'As a user, you are responsible for the safety of your Private Key. We do not store, collect, or have any access to your personal data, messages, or keys. By using Chatme, you acknowledge that your data security rests entirely in your hands through the cryptographic power of the Nostr network.\n\n'
                      'To enhance global discoverability, Chatme maintains a public search index where you can voluntarily link a username to your Public Key. This registry acts solely as a directory to help others find you and does not grant us any access to your private communications or encrypted data. Your sovereignty remains intact as this index is mathematically decoupled from your message content, ensuring that even with a public handle, your privacy remains unbreachable.\n\n'
                      'Should you prefer not to use our global discovery system, you may still use Chatme freely by adding contacts manually. In this case, your username and Public Key will not be indexed, ensuring your identity remains invisible to the public search according to your chosen level of privacy.',
                  style: TextStyle(fontSize: 14, height: 1.6, color: textSecondary),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 32),
                Divider(color: textSecondary.withAlpha(51)),
                const SizedBox(height: 16),
                Text(
                  'End of Privacy Policy',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300, color: textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;

    // Logic Warna sesuai AppearancePage
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: _getAvatarColor(settings.myPubkey),
                    child: Text(
                      ((!_isEditing && _currentHandle.isNotEmpty)
                          ? _currentHandle[0].toUpperCase()
                          : (settings.myName.isNotEmpty ? settings.myName[0].toUpperCase() : '?')),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                      (!_isEditing && _currentHandle.isNotEmpty)
                          ? _currentHandle.split('@')[0]
                          : settings.myName,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary)
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
                side: BorderSide(color: borderColor, width: 0.5),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(
                  AppSettings.instance.isNip05Verified ? Icons.verified_rounded : Icons.verified_user_rounded,
                  color: AppSettings.instance.isNip05Verified ? Colors.blue : textPrimary,
                ),
                title: Text(
                  AppSettings.instance.myNip05.isNotEmpty ? AppSettings.instance.myNip05 : 'Claim your ID',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const GlobalIdPage()),
                  );
                  setState(() {
                    _currentHandle = AppSettings.instance.myNip05;
                    _isEditing = _currentHandle.isEmpty;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Your Public Key', textSecondary),
            Card(
              elevation: 0,
              color: cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5)
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: SelectableText(
                  settings.myPubkey,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textSecondary),
                ),
                trailing: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: settings.myPubkey));
                      HapticFeedback.lightImpact();
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: textSecondary.withAlpha(20), shape: BoxShape.circle),
                      child: Icon(Icons.copy_rounded, color: textSecondary, size: 18),
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
                side: BorderSide(color: borderColor, width: 0.5),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.swap_horiz_rounded, color: textPrimary, size: 18),
                title: Text('Key Converter', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KeyConverterPage()),
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
                side: BorderSide(color: borderColor, width: 0.5),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Remix.server_fill, color: textPrimary, size: 18),
                title: Text('Relay Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RelayStatusPage(relayManager: widget.relayManager)),
                ),
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
                  side: BorderSide(color: borderColor, width: 0.5)
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Remix.eye_fill, color: textPrimary, size: 18),
                    title: Text('Recovery Phrase', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () => _showMnemonicDialog(context),
                  ),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 56),
                  ListTile(
                    leading: Icon(Remix.key_fill, color: textPrimary, size: 18),
                    title: Text('Security Vault', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () => _showBackupDialog(context),
                  ),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 56),
                  ListTile(
                    leading: Icon(Icons.settings_backup_restore_rounded, color: textPrimary, size: 18),
                    title: Text('Restore Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () => _showRestoreDialog(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Appearance', textSecondary),
            Card(
              elevation: 0,
              color: cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5)
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.brightness_6_outlined, color: textPrimary, size: 18),
                title: Text('Theme', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                onTap: () => _showThemeDialog(context),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Information', textSecondary),
            Card(
              elevation: 0,
              color: cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor, width: 0.5)
              ),
              child: Column(
                children: [
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    leading: Icon(Icons.privacy_tip_outlined, color: textPrimary, size: 18),
                    title: Text('Privacy Policy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () => _showPrivacyDialog(context, bgColor, textPrimary, textSecondary),
                  ),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 56),
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    leading: Icon(Icons.article_outlined, color: textPrimary, size: 18),
                    title: Text('Licenses', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                    trailing: Icon(Icons.chevron_right_rounded, color: textSecondary),
                    onTap: () async {
                      final List<LicenseEntry> licenses = await LicenseRegistry.licenses.toList();
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
                              title: Text('Licenses', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary)),
                              leading: IconButton(
                                icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                            body: ListView.builder(
                              padding: const EdgeInsets.all(24.0),
                              itemCount: licenses.length,
                              itemBuilder: (context, index) {
                                final entry = licenses[index];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.packages.join(', '), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textPrimary)),
                                    const SizedBox(height: 8),
                                    ...entry.paragraphs.map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(p.text, style: TextStyle(fontSize: 14, height: 1.6, color: textSecondary)),
                                    )),
                                    if (index < licenses.length - 1) Divider(color: borderColor, height: 48),
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
                  side: BorderSide(color: borderColor, width: 0.5)
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildGuideStep(context, 1, 'Set your handle in Global ID to be searchable', textPrimary),
                    _buildGuideStep(context, 2, 'Or copy your Public Key to share privately', textPrimary),
                    _buildGuideStep(context, 3, 'Go to Contacts to search name or paste key', textPrimary),
                    _buildGuideStep(context, 4, 'Add them to your verified contact list', textPrimary),
                    _buildGuideStep(context, 5, 'Start chatting securely in Chats tab', textPrimary),
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
                side: BorderSide(color: borderColor, width: 0.5),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(Icons.info_outline_rounded, color: textPrimary, size: 18),
                title: Text('Version', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary)),
                trailing: Text('0.1.1-beta', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textSecondary)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}