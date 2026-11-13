import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/chatme_buttons.dart';
import '../../core/theme/chatme_colors.dart';
import '../../core/utils/key_utils.dart';
import '../../widgets/chatme_notice.dart';

class KeyConverterPage extends StatefulWidget {
  const KeyConverterPage({super.key});

  @override
  State<KeyConverterPage> createState() => _KeyConverterPageState();
}

class _KeyConverterPageState extends State<KeyConverterPage> {
  final TextEditingController _pubkeyController = TextEditingController();
  final TextEditingController _privkeyController = TextEditingController();

  String _npubResult = '';
  String _nsecResult = '';
  bool _hasNpub = false;
  bool _hasNsec = false;

  @override
  void dispose() {
    _pubkeyController.dispose();
    _privkeyController.dispose();
    super.dispose();
  }

  void _convertPubkey() {
    final input = _pubkeyController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      if (input.startsWith('npub')) {
        _npubResult = KeyUtils.fromNpub(input);
      } else if (input.length == 64) {
        _npubResult = KeyUtils.toNpub(input);
      } else {
        _npubResult = 'Invalid input';
      }
      _hasNpub = true;
    });
  }

  void _convertPrivkey() {
    final input = _privkeyController.text.trim();
    if (input.isEmpty) return;

    setState(() {
      if (input.startsWith('nsec')) {
        _nsecResult = KeyUtils.fromNsec(input);
      } else if (input.length == 64) {
        _nsecResult = KeyUtils.toNsec(input);
      } else {
        _nsecResult = 'Invalid input';
      }
      _hasNsec = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = ChatmeColors.backgroundPrimary;
    const cardColor = ChatmeColors.surfaceMenu;
    const borderColor = ChatmeColors.borderSubtle;
    const textSecondary = ChatmeColors.textSecondary;
    const textPrimary = ChatmeColors.textPrimary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Key Converter',
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
                  'Convert between hex and npub/nsec format. Each section works independently.',
            ),

            const SizedBox(height: 28),

            // ===== PUBLIC KEY SECTION =====
            const Text(
              'PUBLIC KEY',
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
              child: TextField(
                controller: _pubkeyController,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                onChanged: (_) => setState(() {
                  _hasNpub = false;
                  _npubResult = '';
                }),
                decoration: InputDecoration(
                  hintText: 'Paste hex or npub',
                  hintStyle: const TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.only(
                      left: 16, right: 8, top: 14, bottom: 14),
                  border: InputBorder.none,
                  suffixIcon: GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _pubkeyController.text = data!.text!.trim();
                        HapticFeedback.lightImpact();
                        setState(() {
                          _hasNpub = false;
                          _npubResult = '';
                        });
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.content_paste_rounded,
                          size: 18, color: textSecondary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _convertPubkey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: ChatmeButtonStyles.primaryDecoration(),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 16,
                      color: ChatmeButtonStyles.primaryForeground,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Convert',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ChatmeButtonStyles.primaryForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_hasNpub) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pubkeyController.text.trim().startsWith('npub')
                          ? 'HEX PUBLIC KEY'
                          : 'NPUB',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _npubResult,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _npubResult == 'Invalid input'
                            ? ChatmeColors.statusDanger
                            : textSecondary,
                        height: 1.6,
                      ),
                    ),
                    if (_npubResult != 'Invalid input') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _npubResult));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied!'),
                                duration: Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: ChatmeButtonStyles.chipDecoration(),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 13,
                                  color: ChatmeColors.textSecondary,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: ChatmeColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),
            const Divider(height: 0.5, thickness: 0.5, color: borderColor),
            const SizedBox(height: 28),

            // ===== PRIVATE KEY SECTION =====
            const Text(
              'PRIVATE KEY',
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
              child: TextField(
                controller: _privkeyController,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                onChanged: (_) => setState(() {
                  _hasNsec = false;
                  _nsecResult = '';
                }),
                decoration: InputDecoration(
                  hintText: 'Paste hex or nsec',
                  hintStyle: const TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.only(
                      left: 16, right: 8, top: 14, bottom: 14),
                  border: InputBorder.none,
                  suffixIcon: GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _privkeyController.text = data!.text!.trim();
                        HapticFeedback.lightImpact();
                        setState(() {
                          _hasNsec = false;
                          _nsecResult = '';
                        });
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.content_paste_rounded,
                          size: 18, color: textSecondary),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _convertPrivkey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: ChatmeButtonStyles.primaryDecoration(),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 16,
                      color: ChatmeButtonStyles.primaryForeground,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Convert',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ChatmeButtonStyles.primaryForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_hasNsec) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _privkeyController.text.trim().startsWith('nsec')
                          ? 'HEX PRIVATE KEY'
                          : 'NSEC',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _nsecResult,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _nsecResult == 'Invalid input'
                            ? ChatmeColors.statusDanger
                            : textSecondary,
                        height: 1.6,
                      ),
                    ),
                    if (_nsecResult != 'Invalid input') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _nsecResult));
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied!'),
                                duration: Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: ChatmeButtonStyles.chipDecoration(),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 13,
                                  color: ChatmeColors.textSecondary,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Copy',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: ChatmeColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
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
