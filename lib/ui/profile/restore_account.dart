import 'package:flutter/material.dart';
import '../../services/app_settings.dart';
import '../../relay_manager.dart';

class RestoreAccountPage extends StatefulWidget {
  final RelayManager relayManager;

  const RestoreAccountPage({super.key, required this.relayManager});

  @override
  State<RestoreAccountPage> createState() => _RestoreAccountPageState();
}

class _RestoreAccountPageState extends State<RestoreAccountPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
          'Restore Account',
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

            // Warning
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withAlpha(40), width: 0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.red.withAlpha(200), size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This will replace your current account. Make sure you have backed up your keys first.',
                      style: TextStyle(fontSize: 13, color: Colors.red.withAlpha(200), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            Text(
              'PRIVATE KEY OR RECOVERY PHRASE',
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
                controller: _controller,
                maxLines: 5,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: textPrimary),
                decoration: InputDecoration(
                  hintText: 'Paste your hex key or 12-word phrase...',
                  hintStyle: TextStyle(fontSize: 12, color: textSecondary, fontFamily: 'sans-serif'),
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),

            const SizedBox(height: 28),

            GestureDetector(
              onTap: _isLoading ? null : () async {
                final input = _controller.text.trim();
                if (input.isEmpty) return;

                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                setState(() => _isLoading = true);
                try {
                  await AppSettings.instance.importAccount(input);
                  widget.relayManager.disconnect();
                  widget.relayManager.connect();
                  if (mounted) navigator.pop();
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
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
                    if (_isLoading)
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: textPrimary))
                    else
                      Icon(Icons.settings_backup_restore_rounded, size: 16, color: textPrimary),
                    const SizedBox(width: 8),
                    Text(
                      _isLoading ? 'Restoring...' : 'Restore account',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}