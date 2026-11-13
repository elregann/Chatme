import 'package:hive/hive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:remixicon/remixicon.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../widgets/chatme_notice.dart';

class RecoveryPhrasePage extends StatefulWidget {
  const RecoveryPhrasePage({super.key});

  @override
  State<RecoveryPhrasePage> createState() => _RecoveryPhrasePageState();
}

class _RecoveryPhrasePageState extends State<RecoveryPhrasePage> {
  bool _isRevealed = false;

  @override
  Widget build(BuildContext context) {
    const bgColor = ChatmeColors.backgroundPrimary;
    const cardColor = ChatmeColors.surfaceMenu;
    const borderColor = ChatmeColors.borderSubtle;
    const textSecondary = ChatmeColors.textSecondary;
    const textPrimary = ChatmeColors.textPrimary;

    final settingsBox = Hive.box('settings');
    final String displayMnemonic =
        settingsBox.get('my_mnemonic', defaultValue: '');
    final bool hasMnemonic = displayMnemonic.isNotEmpty;
    final List<String> words = hasMnemonic ? displayMnemonic.split(' ') : [];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Recovery Phrase',
          style: TextStyle(
              fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (hasMnemonic)
            IconButton(
              icon: Icon(
                _isRevealed ? Remix.eye_off_line : Remix.eye_line,
                size: 18,
                color: textSecondary,
              ),
              onPressed: () => setState(() => _isRevealed = !_isRevealed),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChatmeNotice(
              icon: Icons.info_outline_rounded,
              message: hasMnemonic
                  ? 'Keep these 12 words safe. Anyone with them can access your account.'
                  : 'Recovery phrase is not available because you logged in using a private key.',
              iconColor: hasMnemonic
                  ? ChatmeColors.statusWarning
                  : ChatmeColors.accentPrimary,
            ),

            const SizedBox(height: 28),

            // Label + status
            Row(
              children: [
                Text(
                  hasMnemonic ? 'YOUR 12 WORDS' : 'NOT AVAILABLE',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                      color: textSecondary),
                ),
                const Spacer(),
                if (hasMnemonic)
                  Text(
                    _isRevealed ? 'Visible' : 'Hidden',
                    style: const TextStyle(fontSize: 11, color: textSecondary),
                  ),
              ],
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
                  ? _isRevealed
                      ? GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.8,
                          ),
                          itemCount: words.length,
                          itemBuilder: (context, index) {
                            return Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: ChatmeColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: borderColor, width: 0.5),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: textSecondary,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      words[index],
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: textPrimary,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : GestureDetector(
                          onTap: () => setState(() => _isRevealed = true),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(
                                    color: ChatmeColors.surfaceRaised,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.lock_outline_rounded,
                                      size: 20, color: textSecondary),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Tap to reveal',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: textSecondary,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '12 words hidden for security',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: textSecondary.withAlpha(150)),
                                ),
                              ],
                            ),
                          ),
                        )
                  : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.key_off_rounded,
                              size: 14, color: textSecondary),
                          SizedBox(width: 8),
                          Text('No recovery phrase',
                              style: TextStyle(
                                  fontSize: 13, color: textSecondary)),
                        ],
                      ),
                    ),
            ),

            if (hasMnemonic && _isRevealed) ...[
              const SizedBox(height: 28),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: displayMnemonic));
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Recovery phrase copied, keep it safe'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: ChatmeButtonStyles.neutralDecoration(),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: ChatmeButtonStyles.neutralForeground,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Copy all words',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: ChatmeButtonStyles.neutralForeground,
                        ),
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
