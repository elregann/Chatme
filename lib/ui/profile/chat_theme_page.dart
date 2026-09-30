import 'package:flutter/material.dart';
import '../../services/app_settings.dart';

class ChatThemePage extends StatefulWidget {
  const ChatThemePage({super.key});

  @override
  State<ChatThemePage> createState() => _ChatThemePageState();
}

class _ChatThemePageState extends State<ChatThemePage> {
  late String _selectedTheme;

  @override
  void initState() {
    super.initState();
    _selectedTheme = AppSettings.instance.roomChatTheme;
  }

  Future<void> _selectTheme(String id, String name) async {
    setState(() {
      _selectedTheme = id;
    });
    await AppSettings.instance.setRoomChatTheme(id);
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
          'Room Chat Theme',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AVAILABLE THEMES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
            ),
            const SizedBox(height: 8),

            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Column(
                children: [
                  _buildThemeOption(
                    context: context,
                    id: 'default',
                    name: 'Default (Standard)',
                    description: 'Follows application appearance mode',
                    previewColors: [Colors.grey.shade400, Colors.grey.shade700],
                    borderColor: borderColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    isFirst: true,
                  ),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor),
                  _buildThemeOption(
                    context: context,
                    id: 'nostr_cyber',
                    name: 'Nostr Cyber / Amethyst',
                    description: 'Deep purple & electric violet accents (Absolute Theme)',
                    previewColors: [const Color(0xFF2A1B3D), const Color(0xFF7B2CBF)],
                    borderColor: borderColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Note: Applying a custom room chat theme overrides individual light/dark mode settings specifically inside chat rooms.',
              style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required String id,
    required String name,
    required String description,
    required List<Color> previewColors,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isSelected = _selectedTheme == id;

    return GestureDetector(
      onTap: () => _selectTheme(id, name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            topLeft: isFirst ? const Radius.circular(12) : Radius.zero,
            topRight: isFirst ? const Radius.circular(12) : Radius.zero,
            bottomLeft: isLast ? const Radius.circular(12) : Radius.zero,
            bottomRight: isLast ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: previewColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: borderColor, width: 0.5),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? textPrimary : textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, size: 18, color: textPrimary),
          ],
        ),
      ),
    );
  }
}
