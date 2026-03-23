import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/key_utils.dart';

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
          'Key Converter',
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

            // Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purpleAccent.withAlpha(30), width: 0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.purpleAccent.withAlpha(200), size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Convert between hex and npub/nsec format. Each section works independently.',
                      style: TextStyle(fontSize: 13, color: Colors.purpleAccent.withAlpha(200), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ===== PUBLIC KEY SECTION =====
            Text(
              'PUBLIC KEY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
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
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                onChanged: (_) => setState(() {
                  _hasNpub = false;
                  _npubResult = '';
                }),
                decoration: InputDecoration(
                  hintText: 'Paste hex or npub',
                  hintStyle: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 14, bottom: 14),
                  border: InputBorder.none,
                  suffixIcon: GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _pubkeyController.text = data!.text!.trim();
                        HapticFeedback.lightImpact();
                        setState(() { _hasNpub = false; _npubResult = ''; });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.content_paste_rounded, size: 18, color: textSecondary),
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 16, color: textPrimary),
                    const SizedBox(width: 8),
                    Text('Convert', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary)),
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
                      _pubkeyController.text.trim().startsWith('npub') ? 'HEX PUBLIC KEY' : 'NPUB',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _npubResult,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _npubResult == 'Invalid input' ? Colors.red.withAlpha(200) : textSecondary,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: textSecondary),
                                const SizedBox(width: 6),
                                Text('Copy', style: TextStyle(fontSize: 13, color: textSecondary)),
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
            Divider(height: 0.5, thickness: 0.5, color: borderColor),
            const SizedBox(height: 28),

            // ===== PRIVATE KEY SECTION =====
            Text(
              'PRIVATE KEY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
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
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                onChanged: (_) => setState(() {
                  _hasNsec = false;
                  _nsecResult = '';
                }),
                decoration: InputDecoration(
                  hintText: 'Paste hex or nsec',
                  hintStyle: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 14, bottom: 14),
                  border: InputBorder.none,
                  suffixIcon: GestureDetector(
                    onTap: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _privkeyController.text = data!.text!.trim();
                        HapticFeedback.lightImpact();
                        setState(() { _hasNsec = false; _nsecResult = ''; });
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(Icons.content_paste_rounded, size: 18, color: textSecondary),
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.swap_horiz_rounded, size: 16, color: textPrimary),
                    const SizedBox(width: 8),
                    Text('Convert', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary)),
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
                      _privkeyController.text.trim().startsWith('nsec') ? 'HEX PRIVATE KEY' : 'NSEC',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _nsecResult,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: _nsecResult == 'Invalid input' ? Colors.red.withAlpha(200) : textSecondary,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: textSecondary),
                                const SizedBox(width: 6),
                                Text('Copy', style: TextStyle(fontSize: 13, color: textSecondary)),
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