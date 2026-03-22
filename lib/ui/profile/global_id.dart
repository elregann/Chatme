import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../services/app_settings.dart';

class GlobalIdPage extends StatefulWidget {
  const GlobalIdPage({super.key});

  @override
  State<GlobalIdPage> createState() => _GlobalIdPageState();
}

class _GlobalIdPageState extends State<GlobalIdPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final current = AppSettings.instance.myNip05;
    if (current.isNotEmpty) {
      _controller.text = current.split('@')[0];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _claimUsername(String newName, String pubkey) async {
    try {
      const String rtdbUrl = "https://chatme-412d1-default-rtdb.asia-southeast1.firebasedatabase.app";
      final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: rtdbUrl);

      // Cek nama baru
      final newRef = db.ref("usernames/$newName");
      final snapshot = await newRef.get().timeout(const Duration(seconds: 10));
      if (snapshot.exists && snapshot.value != pubkey) return false;

      // Hapus nama lama dulu
      final oldNip05 = AppSettings.instance.myNip05;
      if (oldNip05.isNotEmpty) {
        final oldName = oldNip05.split('@')[0];
        if (oldName != newName) {
          await db.ref("usernames/$oldName").remove();
        }
      }

      // Daftarkan nama baru
      await newRef.set(pubkey);
      return true;
    } catch (e) {
      debugPrint('❌ claimUsername error: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textSecondary = isDark ? Colors.white54 : Colors.black45;
    final textPrimary = isDark ? Colors.white : Colors.black;

    final currentHandle = AppSettings.instance.myNip05;
    final hasHandle = currentHandle.isNotEmpty;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Global ID',
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
                color: Colors.blue.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withAlpha(30), width: 0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.blue.withAlpha(200), size: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Claim a unique username to make it easier for others to find you.',
                      style: TextStyle(fontSize: 13, color: Colors.blue.withAlpha(200), height: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Current handle
            if (hasHandle) ...[
              Text(
                'CURRENT ID',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      AppSettings.instance.isNip05Verified ? Icons.verified_rounded : Icons.verified_user_rounded,
                      color: AppSettings.instance.isNip05Verified ? Colors.blue : Colors.purple,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      currentHandle,
                      style: TextStyle(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Input nama baru
            Text(
              hasHandle ? 'CHANGE TO' : 'CLAIM USERNAME',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text('@', style: TextStyle(fontSize: 16, color: textSecondary, fontWeight: FontWeight.w500)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(fontSize: 14, color: textPrimary),
                      decoration: InputDecoration(
                        hintText: 'username',
                        hintStyle: TextStyle(fontSize: 14, color: textSecondary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('@chatme', style: TextStyle(fontSize: 13, color: textSecondary)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Claim button
            GestureDetector(
              onTap: _isLoading ? null : () async {
                final input = _controller.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
                if (input.length < 3) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Username must be at least 3 characters'), behavior: SnackBarBehavior.floating),
                  );
                  return;
                }

                final messenger = ScaffoldMessenger.of(context);
                setState(() => _isLoading = true);

                final success = await _claimUsername(input, AppSettings.instance.myPubkey);

                if (!mounted) return;
                setState(() => _isLoading = false);

                if (success) {
                  await AppSettings.instance.updateNip05('$input@chatme', true);
                  if (!mounted) return;
                  setState(() {});
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '$input@chatme claimed!',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Username already taken',
                        style: TextStyle(color: Colors.white),
                      ),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
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
                      Icon(Icons.verified_user_rounded, size: 16, color: textPrimary),
                    const SizedBox(width: 8),
                    Text(
                      _isLoading ? 'Claiming...' : (hasHandle ? 'Update ID' : 'Claim ID'),
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