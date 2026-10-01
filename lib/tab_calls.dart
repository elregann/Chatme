// tab_calls.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:remixicon/remixicon.dart';
import 'models/call_log.dart';
import 'models/contact.dart';
import 'relay_manager.dart';
import 'call_manager.dart';
import 'core/utils/ui_utils.dart';
import 'widgets/user_avatar.dart';

class CallsScreen extends StatefulWidget {
  final RelayManager relayManager;

  const CallsScreen({super.key, required this.relayManager});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  String _formatCallTimestamp(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final now = DateTime.now();

    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today, $timeStr';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Yesterday, $timeStr';
    }

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${date.day} ${months[date.month - 1]}, $timeStr';
  }

  void _callPeer(BuildContext context, String peerPubkey, String peerName) {
    HapticFeedback.lightImpact();
    final peerColor = UIUtils.getAvatarColor(peerPubkey);

    CallManager.instance.startCallFlow(
      context: context,
      peerName: peerName,
      peerPubkey: peerPubkey,
      relay: widget.relayManager,
      peerColor: peerColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calls',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<CallLog>('call_logs').listenable(),
        builder: (context, Box<CallLog> box, _) {
          List<CallLog> logs = box.values.toList();
          logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Remix.phone_line,
                    size: 64,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No call history yet',
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 72,
              color: isDark ? Colors.white10 : Colors.black.withAlpha(10),
            ),
            itemBuilder: (context, index) {
              final log = logs[index];
              return _buildCallLogItem(context, log, isDark);
            },
          );
        },
      ),
    );
  }

  Widget _buildCallLogItem(BuildContext context, CallLog log, bool isDark) {
    final contactsBox = Hive.box<Contact>('contacts');
    final contact = contactsBox.get(log.peerPubkey);
    final displayName = (contact?.name != null && contact!.name.isNotEmpty)
        ? contact.name
        : log.peerName;

    IconData directionIcon;
    Color iconColor;
    String statusLabel;

    if (log.isMissed) {
      directionIcon = Icons.call_missed;
      iconColor = Colors.red;
      statusLabel = 'Missed Calls';
    } else if (log.isIncoming) {
      directionIcon = Icons.call_received;
      iconColor = Colors.green;
      statusLabel = log.formattedDuration.isNotEmpty ? 'Incoming Calls (${log.formattedDuration})' : 'Incoming Calls';
    } else {
      directionIcon = Icons.call_made;
      iconColor = Colors.blue;
      statusLabel = log.formattedDuration.isNotEmpty ? 'Outgoing Calls (${log.formattedDuration})' : 'Outgoing Calls';
    }

    return Dismissible(
      key: Key(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Remix.delete_bin_line, color: Colors.white),
      ),
      onDismissed: (_) {
        log.delete();
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: UserAvatar(
          pubkey: log.peerPubkey,
          name: displayName,
          radius: 22,
          relayManager: widget.relayManager,
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: log.isMissed ? Colors.red : (isDark ? Colors.white : Colors.black87),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(directionIcon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Text(
              statusLabel,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const Text(' • '),
            Text(
              _formatCallTimestamp(log.timestamp),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Remix.phone_fill, color: Colors.green),
          tooltip: 'Call',
          onPressed: () => _callPeer(context, log.peerPubkey, displayName),
        ),
        onTap: () => _callPeer(context, log.peerPubkey, displayName),
      ),
    );
  }
}
