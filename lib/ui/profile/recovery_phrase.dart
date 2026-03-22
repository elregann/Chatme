import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

class RecoveryPhrasePage extends StatelessWidget {
  const RecoveryPhrasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final textPrimary = isDark ? Colors.white : Colors.black;

    final settingsBox = Hive.box('settings');
    final String displayMnemonic = settingsBox.get('my_mnemonic', defaultValue: '');
    final bool hasMnemonic = displayMnemonic.isNotEmpty;
    final List<String> words = hasMnemonic ? displayMnemonic.split(' ') : [];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Recovery Phrase',
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

            // Warning atau info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasMnemonic
                    ? Colors.orange.withAlpha(15)
                    : Colors.blue.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasMnemonic
                      ? Colors.orange.withAlpha(40)
                      : Colors.blue.withAlpha(30),
                  width: 0.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    hasMnemonic ? Icons.info_outline_rounded : Icons.info_outline_rounded,
                    color: hasMnemonic
                        ? Colors.orange.withAlpha(200)
                        : Colors.blue.withAlpha(200),
                    size: 14,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasMnemonic
                          ? 'Keep these 12 words safe. Anyone with them can access your account.'
                          : 'Recovery phrase is not available because you logged in using a private key.',
                      style: TextStyle(
                        fontSize: 13,
                        color: hasMnemonic
                            ? Colors.orange.withAlpha(200)
                            : Colors.blue.withAlpha(200),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Label
            Text(
              hasMnemonic ? 'YOUR 12 WORDS' : 'NOT AVAILABLE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
            ),
            const SizedBox(height: 8),

            // Words grid atau placeholder
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: hasMnemonic
                  ? GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.8,
                ),
                itemCount: words.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${index + 1}',
                          style: TextStyle(fontSize: 10, color: textSecondary, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            words[index],
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: textPrimary, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
                  : Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.key_off_rounded, size: 14, color: textSecondary),
                    const SizedBox(width: 8),
                    Text('No recovery phrase', style: TextStyle(fontSize: 13, color: textSecondary)),
                  ],
                ),
              ),
            ),

            if (hasMnemonic) ...[
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: displayMnemonic));
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Recovery phrase copied — keep it safe'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
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
                      Icon(Icons.copy_rounded, size: 16, color: textPrimary),
                      const SizedBox(width: 8),
                      Text(
                        'Copy all words',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}