import 'package:flutter/material.dart';
import '../../services/app_settings.dart';

class AppearancePage extends StatefulWidget {
  final Function(ThemeMode) onThemeToggle;

  const AppearancePage({super.key, required this.onThemeToggle});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late ThemeMode _currentMode;

  @override
  void initState() {
    super.initState();
    _currentMode = AppSettings.instance.themeMode;
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
          'Appearance',
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
              'THEME',
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
                  _buildThemeOption(context, 'System default', Icons.brightness_auto_rounded, ThemeMode.system, borderColor, textPrimary, textSecondary, isFirst: true),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor),
                  _buildThemeOption(context, 'Light', Icons.light_mode_rounded, ThemeMode.light, borderColor, textPrimary, textSecondary),
                  Divider(height: 0.5, thickness: 0.5, color: borderColor),
                  _buildThemeOption(context, 'Dark', Icons.dark_mode_rounded, ThemeMode.dark, borderColor, textPrimary, textSecondary, isLast: true),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(
      BuildContext context,
      String label,
      IconData icon,
      ThemeMode mode,
      Color borderColor,
      Color textPrimary,
      Color textSecondary, {
        bool isFirst = false,
        bool isLast = false,
      }) {
    final isSelected = _currentMode == mode;

    return GestureDetector(
      onTap: () {
        setState(() => _currentMode = mode);
        widget.onThemeToggle(mode);
      },
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
            Icon(icon, size: 18, color: isSelected ? textPrimary : textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  color: isSelected ? textPrimary : textSecondary,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, size: 16, color: textPrimary),
          ],
        ),
      ),
    );
  }
}