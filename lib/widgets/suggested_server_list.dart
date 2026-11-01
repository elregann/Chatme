// suggested_server_list.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/server_lists.dart';

/// A card of server addresses that can only be copied, one icon per row.
class SuggestedServerList extends StatelessWidget {
  final String title;
  final String description;
  final List<String> servers;

  const SuggestedServerList({
    super.key,
    required this.title,
    required this.description,
    required this.servers,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8);
    final borderColor = isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;

    final rows = <Widget>[];
    for (var i = 0; i < servers.length; i++) {
      final url = servers[i];
      if (i > 0) rows.add(Divider(height: 0.5, thickness: 0.5, color: borderColor, indent: 16));
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                ServerAddress.displayHost(url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: textPrimary),
              ),
            ),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                HapticFeedback.selectionClick();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.copy_rounded, size: 18, color: textSecondary),
              ),
            ),
          ],
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2, color: textSecondary),
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 13, height: 1.35, color: textSecondary)),
        ],
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}
