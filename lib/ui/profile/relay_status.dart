// relay_status.dart

import '../../widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import '../../relay_manager.dart';
import '../../services/app_settings.dart';
import '../../services/server_lists.dart';
import '../../widgets/editable_server_list.dart';

class RelayStatusPage extends StatelessWidget {
  final RelayManager relayManager;

  const RelayStatusPage({super.key, required this.relayManager});

  String _statusLabel(String url) =>
      relayManager.connectionStatus[url] == true ? 'Connected' : 'Connecting';

  Color _statusColor(String url) =>
      relayManager.connectionStatus[url] == true ? Colors.green : Colors.orange;

  void _remove(BuildContext context, RelayGroup group, String url) async {
    final edit = await relayManager.removeRelay(group, url);
    if (!context.mounted || edit.ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(changeMessage(edit.change, fileServer: false))));
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset to defaults?',
      message: 'Your own relays will be removed and the built in ones come back.',
      confirmLabel: 'Reset',
    );
    if (confirmed) await relayManager.resetRelaysToDefaults();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Relays',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([relayManager.relayListVersion, relayManager.connectedCount]),
        builder: (context, _) {
          final inbox = AppSettings.instance.inboxRelays;
          final other = AppSettings.instance.otherRelays;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EditableServerList(
                  title: 'INBOX RELAYS',
                  description:
                      'Where people send you messages. These relays are shown on your profile and in your QR code, so others know where to reach you.',
                  servers: inbox,
                  defaults: RelayDefaults.inbox,
                  addLabel: 'Add inbox relay',
                  hint: 'relay.example.com',
                  fileServer: false,
                  onSubmit: inbox.length < ListLimits.inboxMax
                      ? (input) => relayManager.addRelay(RelayGroup.inbox, input)
                      : null,
                  onRemove: (url) => _remove(context, RelayGroup.inbox, url),
                  statusLabel: _statusLabel,
                  statusColor: _statusColor,
                  warning: inbox.length > ListLimits.inboxRecommended
                      ? 'Three inbox relays are enough. More use extra data and battery.'
                      : null,
                ),
                const SizedBox(height: 28),
                EditableServerList(
                  title: 'OTHER RELAYS',
                  description: 'Extra relays Chatme also connects to, used for profiles and as more routes.',
                  servers: other,
                  defaults: RelayDefaults.other,
                  addLabel: 'Add relay',
                  hint: 'relay.example.com',
                  fileServer: false,
                  onSubmit: other.length < ListLimits.otherMax
                      ? (input) => relayManager.addRelay(RelayGroup.other, input)
                      : null,
                  onRemove: (url) => _remove(context, RelayGroup.other, url),
                  statusLabel: _statusLabel,
                  statusColor: _statusColor,
                ),
                const SizedBox(height: 20),
                Text(
                  'Relays you add can see your IP address, but not the content of your messages.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: textSecondary),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _reset(context),
                  child: const Text('Reset to defaults'),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}
