import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'relaymanager.dart';

class ProfileScreen extends StatelessWidget {
  final Function(ThemeMode) onThemeToggle;
  final RelayManager relayManager;

  const ProfileScreen({
    super.key,
    required this.onThemeToggle,
    required this.relayManager,
  });

  // Warna avatar berdasarkan pubkey
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
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.grey),
      ),
    );
  }

  // Widget step guide
  Widget _buildGuideStep(BuildContext context, int step, String text) {
    final settings = AppSettings.instance;
    final avatarColor = _getAvatarColor(settings.myPubkey);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: avatarColor.withAlpha(204),
            child: Text(
              step.toString(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
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
  Future<void> _showBackupDialog(BuildContext context) async {
    final settings = AppSettings.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security_rounded, color: Colors.orange, size: 32),
            ),
            const SizedBox(height: 12),
            const Text('Backup Keys', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(13),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withAlpha(51)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'NEVER share your Private Key. It grants full access to your account.',
                        style: TextStyle(color: isDark ? Colors.red[200] : Colors.red[800], fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _keyCard(context, 'PUBLIC KEY', settings.myPubkey, Icons.visibility_outlined, Colors.blue),
              const SizedBox(height: 16),
              _keyCard(context, 'PRIVATE KEY', settings.myPrivkey, Icons.vpn_key_outlined, Colors.orange, isSensitive: true),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: Colors.grey[600])),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              foregroundColor: Colors.grey[600],
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: settings.exportKeys()));
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            label: const Text('Copy All'),
          ),
        ],
      ),
    );
  }

  // Dialog restore account
  Future<void> _showRestoreDialog(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Restore Account', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your 64-character Private Key to recover your identity.', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 2,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Paste Hex Private Key...',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.vpn_key_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final privkey = controller.text.trim();
              if (privkey.length == 64) {
                try {
                  await AppSettings.instance.importAccount(privkey);
                  relayManager.disconnect();
                  relayManager.connect();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Account successfully restored!'),
                        backgroundColor: Colors.green
                    ));
                  }
                } catch (e) {
                  DebugLogger.log('Restore error: $e', type: 'ERROR');
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Invalid key length!')
                ));
              }
            },
            child: const Text('Restore Now', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Dialog Pilih Tema
  Future<void> _showThemeDialog(BuildContext context) async {
    final currentMode = AppSettings.instance.themeMode;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        title: const Text(
          'Choose Theme',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: RadioGroup<ThemeMode>(
          groupValue: currentMode,
          onChanged: (ThemeMode? value) {
            if (value != null) {
              onThemeToggle(value);
              Navigator.pop(context);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _themeOption(context, 'System default', ThemeMode.system),
              _themeOption(context, 'Light', ThemeMode.light),
              _themeOption(context, 'Dark', ThemeMode.dark),
            ],
          ),
        ),
      ),
    );
  }


  // Helper untuk baris pilihan tema
  Widget _themeOption(BuildContext context, String title, ThemeMode mode) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: RadioListTile<ThemeMode>(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        value: mode,
        selectedTileColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        activeColor: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  // Dialog Privacy Policy
  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const SingleChildScrollView(
          child: Text(
            'Chatme is a decentralized communication tool built on the Nostr protocol, where privacy is inherent because we operate without central servers. Every message is locally secured with end-to-end encryption using your Private Key, ensuring that you alone own your data; however, this absolute sovereignty means account recovery is impossible if your keys are lost. While our ecosystem promotes transparency through open-source relays, please be aware that metadata such as your IP address may remain visible to the specific relay providers you connect to.',
            style: TextStyle(fontSize: 13, height: 1.6),
            textAlign: TextAlign.justify,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }

  // Widget card untuk menampilkan key
  Widget _keyCard(BuildContext context, String title, String key, IconData icon, Color color, {bool isSensitive = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: key));
              HapticFeedback.lightImpact();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor.withAlpha(30)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      key,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isSensitive ? Colors.orange : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.copy_rounded, size: 16, color: Theme.of(context).colorScheme.primary.withAlpha(150)),
                ],
              ),
            ),
          ),
        ),
      ],
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
                    radius: 50,
                    backgroundColor: _getAvatarColor(settings.myPubkey),
                    child: Text(
                      settings.myName.isNotEmpty ? settings.myName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(settings.myName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildConnectionStatus(),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('Your Public Key'),
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
                onTap: () {
                  Clipboard.setData(ClipboardData(text: settings.myPubkey));
                  HapticFeedback.lightImpact();
                },
                title: SelectableText(
                  settings.myPubkey,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
                trailing: Icon(
                    Icons.copy_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('Security & Account'),
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
                    leading: const Icon(Icons.vpn_key_outlined, color: Colors.blue),
                    title: const Text('Backup Your Keys', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Save your private identity', style: TextStyle(fontSize: 12)),
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
                    leading: const Icon(Icons.history_rounded, color: Colors.red),
                    title: const Text('Restore Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: const Text('Use private key to login', style: TextStyle(fontSize: 12)),
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
                leading: const Icon(Icons.brightness_6_outlined, color: Colors.purple),
                title: const Text('Theme', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  AppSettings.instance.themeMode == ThemeMode.system
                      ? 'System default'
                      : AppSettings.instance.themeMode == ThemeMode.dark ? 'Dark' : 'Light',
                  style: const TextStyle(fontSize: 12),
                ),
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
                    leading: const Icon(Icons.privacy_tip_outlined, color: Colors.teal),
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
                    leading: const Icon(Icons.article_outlined, color: Colors.blueGrey),
                    title: const Text('Licenses', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showLicensePage(
                      context: context,
                    ),
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
                    _buildGuideStep(context, 1, 'Copy your public key above'),
                    _buildGuideStep(context, 2, 'Share it with a friend'),
                    _buildGuideStep(context, 3, 'Add their key in Contacts tab'),
                    _buildGuideStep(context, 4, 'Start chatting in Chats tab'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: Column(
                children: [
                  const Opacity(
                    opacity: 0.5,
                    child: Text('ChatMe Decentralized Messenger\nOwned by You, Not by Cloud',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Text('Version 1.0.0-Alpha',
                      style: TextStyle(fontSize: 10, color: Colors.grey.withAlpha(127))),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget status koneksi relay
  Widget _buildConnectionStatus() {
    return ValueListenableBuilder<bool>(
      valueListenable: relayManager.isConnected,
      builder: (context, isConnected, _) {
        final color = isConnected ? Colors.green : Colors.orange;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withAlpha(76)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 8),
              Text(
                isConnected ? 'Relay Connected' : 'Relay Connecting',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}