// contact_profile.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../chat_manager.dart';
import '../../core/utils/key_utils.dart';
import '../../models/contact.dart';
import '../../relay_manager.dart';
import '../../services/app_settings.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/voice_history_list.dart';
import '../qr/qr_code_page.dart';

class ContactProfilePage extends StatelessWidget {
  final Contact contact;
  final RelayManager relayManager;

  const ContactProfilePage({
    super.key,
    required this.contact,
    required this.relayManager,
  });

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<Contact>('contacts');
    return ValueListenableBuilder<Box<Contact>>(
      valueListenable: box.listenable(keys: [contact.pubkey]),
      builder: (context, box, _) => _buildPage(context, box.get(contact.pubkey) ?? contact),
    );
  }

  Widget _buildPage(BuildContext context, Contact current) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final textPrimary = isDark ? Colors.white : Colors.black;
    final displayName = AppSettings.getContactDisplayName(current);
    final nprofile = KeyUtils.toNprofile(current.pubkey, relays: RelayManager.dmInboxRelays);

    const pillColor = Colors.blue;
    final tabBar = Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: pillColor.withAlpha(isDark ? 50 : 35),
          borderRadius: BorderRadius.circular(19),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(3),
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelColor: pillColor,
        unselectedLabelColor: textSecondary,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Media'),
          Tab(text: 'Voice'),
        ],
      ),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.qr_code_2_rounded, color: textPrimary, size: 26),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrCodePage(
                    pubkey: current.pubkey,
                    name: displayName,
                    relayManager: relayManager,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  children: [
                    UserAvatar(
                      pubkey: current.pubkey,
                      name: displayName,
                      radius: 56,
                      relayManager: relayManager,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                    if (current.hasGlobalId) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${current.name}@chatme',
                        style: TextStyle(fontSize: 13, color: textSecondary),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _CopyChip(
                      label: _shorten(nprofile),
                      value: nprofile,
                      message: 'nprofile copied',
                      cardColor: cardColor,
                      borderColor: borderColor,
                      textColor: textSecondary,
                    ),
                    const SizedBox(height: 8),
                    _CopyChip(
                      label: KeyUtils.formatDisplayName(current.pubkey),
                      value: KeyUtils.toNpub(current.pubkey),
                      message: 'npub copied',
                      cardColor: cardColor,
                      borderColor: borderColor,
                      textColor: textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(tabBar, bgColor),
            ),
          ],
          body: TabBarView(
            children: [
              _EmptyMedia(
                icon: Icons.photo_library_outlined,
                label: 'No shared images or videos yet',
                color: textSecondary,
              ),
              kIsWeb
                  ? _EmptyMedia(
                      icon: Icons.mic_none_rounded,
                      label: 'Voice notes are not available on web yet',
                      color: textSecondary,
                    )
                  : VoiceHistoryList(
                      chatKey: ChatManager.instance.getChatKey(
                        AppSettings.instance.myPubkey,
                        current.pubkey,
                      ),
                      contactName: displayName,
                      empty: _EmptyMedia(
                        icon: Icons.mic_none_rounded,
                        label: 'No voice notes yet',
                        color: textSecondary,
                      ),
                      cardColor: cardColor,
                      borderColor: borderColor,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

String _shorten(String value) {
  if (value.length <= 24) return value;
  return '${value.substring(0, 14)}...${value.substring(value.length - 8)}';
}

class _CopyChip extends StatelessWidget {
  final String label;
  final String value;
  final String message;
  final Color cardColor;
  final Color borderColor;
  final Color textColor;

  const _CopyChip({
    required this.label,
    required this.value,
    required this.message,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: textColor)),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 12, color: textColor),
          ],
        ),
      ),
    );
  }
}

class _EmptyMedia extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EmptyMedia({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color.withAlpha(100)),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 14, color: color)),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget tabBar;
  final Color color;

  _TabBarDelegate(this.tabBar, this.color);

  static const double _height = 52;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: color,
      alignment: Alignment.topCenter,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.color != color;
  }
}
