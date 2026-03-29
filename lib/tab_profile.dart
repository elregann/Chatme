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

  // Widget title section
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Theme.of(context).iconTheme.color),
      ),
    );
  }

  // Widget step guide
  Widget _buildGuideStep(BuildContext context, int step, String text) {
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
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // Dialog backup keys
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

  // Dialog 12 words (Mnemonic)
  void _showMnemonicDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RecoveryPhrasePage()),
    );
  }

  // Dialog restore account
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

  // Dialog Pilih Tema
  void _showThemeDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AppearancePage(onThemeToggle: widget.onThemeToggle),
      ),
    );
  }

  // Dialog Privacy Policy
  void _showPrivacyDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF121212)
                : Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            title: Text(
              'Privacy Policy',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
                size: 18,
              ),
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
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(200),
                  ),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 32),
                Divider(color: Theme.of(context).dividerColor.withAlpha(51)),
                const SizedBox(height: 16),
                Text(
                  'End of Privacy Policy',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(150),
                  ),
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

    return Scaffold(
      appBar: AppBar(
          title: const Text('Profile'),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).iconTheme.color,
                      )
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Global ID'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(
                  AppSettings.instance.isNip05Verified ? Icons.verified_rounded : Icons.verified_user_rounded,
                  color: AppSettings.instance.isNip05Verified ? Colors.blue : Theme.of(context).iconTheme.color,
                ),
                title: Text(
                  AppSettings.instance.myNip05.isNotEmpty ? AppSettings.instance.myNip05 : 'Claim your ID',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
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
            _buildSectionTitle('Your Public Key'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25))
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: SelectableText(
                  settings.myPubkey,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(200),
                  ),
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
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                          Icons.copy_rounded,
                          color: Colors.grey,
                          size: 18
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Tools'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(Icons.swap_horiz_rounded, color: Theme.of(context).iconTheme.color),
                title: const Text('Key Converter', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KeyConverterPage()),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Network'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(Remix.server_fill, color: Theme.of(context).iconTheme.color),
                title: const Text('Relay Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RelayStatusPage(relayManager: widget.relayManager),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Security & Account'),
            Card(
              elevation: 0,
              shadowColor: Colors.black.withAlpha(51),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25))
              ),
              child: Column(
                children: [
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    leading: Icon(Remix.eye_fill, color: Theme.of(context).iconTheme.color),
                    title: const Text('Recovery Phrase', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showMnemonicDialog(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(Remix.key_fill, color: Theme.of(context).iconTheme.color),
                    title: const Text('Security Vault', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showBackupDialog(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    leading: Icon(Icons.settings_backup_restore_rounded, color: Theme.of(context).iconTheme.color),
                    title: const Text('Restore Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showRestoreDialog(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Appearance'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25))
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(Icons.brightness_6_outlined, color: Theme.of(context).iconTheme.color),
                title: const Text('Theme', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showThemeDialog(context),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Information'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25))),
              child: Column(
                children: [
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    leading: Icon(Icons.privacy_tip_outlined, color: Theme.of(context).iconTheme.color),
                    title: const Text('Privacy Policy', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showPrivacyDialog(context),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    leading: Icon(Icons.article_outlined, color: Theme.of(context).iconTheme.color),
                    title: const Text('Licenses', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final List<LicenseEntry> licenses = await LicenseRegistry.licenses.toList();

                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            appBar: AppBar(
                              backgroundColor: Theme.of(context).brightness == Brightness.dark
                                  ? const Color(0xFF121212)
                                  : Colors.white,
                              elevation: 0,
                              scrolledUnderElevation: 0,
                              centerTitle: true,
                              title: Text(
                                'Licenses',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              leading: IconButton(
                                icon: Icon(
                                  Icons.arrow_back_ios_rounded,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                  size: 18,
                                ),
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
                                    Text(
                                      entry.packages.join(', '),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Theme.of(context).textTheme.bodyMedium?.color,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...entry.paragraphs.map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        p.text,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.6,
                                          color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(200),
                                        ),
                                      ),
                                    )),
                                    if (index < licenses.length - 1)
                                      Divider(color: Theme.of(context).dividerColor.withAlpha(51), height: 48),
                                    if (index == licenses.length - 1) ...[
                                      const SizedBox(height: 32),
                                      Divider(color: Theme.of(context).dividerColor.withAlpha(51)),
                                      const SizedBox(height: 16),
                                      Text(
                                        'End of Licenses',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w300,
                                          color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(150),
                                        ),
                                      ),
                                    ],
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
            _buildSectionTitle('How to Chat'),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25))),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildGuideStep(context, 1, 'Set your handle in Global ID to be searchable'),
                    _buildGuideStep(context, 2, 'Or copy your Public Key to share privately'),
                    _buildGuideStep(context, 3, 'Go to Contacts to search name or paste key'),
                    _buildGuideStep(context, 4, 'Add them to your verified contact list'),
                    _buildGuideStep(context, 5, 'Start chatting securely in Chats tab'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(25)),
              ),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: Icon(Icons.info_outline_rounded, color: Theme.of(context).iconTheme.color),
                title: const Text('Version', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                trailing: const Text('1.5`.13', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}