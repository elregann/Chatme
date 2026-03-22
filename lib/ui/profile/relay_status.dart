import 'package:flutter/material.dart';
import '../../relay_manager.dart';

class RelayStatusPage extends StatelessWidget {
  final RelayManager relayManager;

  const RelayStatusPage({super.key, required this.relayManager});

  String _shortName(String url) {
    return url.replaceAll('wss://', '').replaceAll('ws://', '');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Relay Status',
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
              'RELAYS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: isDark ? Colors.white54 : Colors.black45),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<int>(
              valueListenable: relayManager.connectedCount,
              builder: (context, _, __) {
                final status = relayManager.connectionStatus;
                return Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                  child: Column(
                    children: relayManager.relays.asMap().entries.map((entry) {
                      final index = entry.key;
                      final url = entry.value;
                      final isConnected = status[url] ?? false;
                      final isLast = index == relayManager.relays.length - 1;

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isConnected ? Colors.green : Colors.orange,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _shortName(url),
                                    style: TextStyle(fontSize: 13, color: textPrimary),
                                  ),
                                ),
                                Text(
                                  isConnected ? 'Connected' : 'Connecting',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isConnected ? Colors.green : Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isLast)
                            Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 36),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}