// file_servers.dart

import '../../widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import '../../services/app_settings.dart';
import '../../services/blossom_servers.dart';
import '../../services/server_lists.dart';
import '../../widgets/editable_server_list.dart';

class FileServersPage extends StatelessWidget {
  const FileServersPage({super.key});

  void _remove(BuildContext context, String url) async {
    final edit = await BlossomServers.remove(url);
    if (!context.mounted || edit.ok) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(changeMessage(edit.change, fileServer: true))));
  }

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset to defaults?',
      message: 'Your own file servers will be removed and the built in ones come back.',
      confirmLabel: 'Reset',
    );
    if (confirmed) await BlossomServers.reset();
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
          'File servers',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: textPrimary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: AppSettings.instance.blossomVersion,
        builder: (context, _, __) {
          final servers = AppSettings.instance.blossomServers;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EditableServerList(
                  title: 'FILE SERVERS',
                  description:
                      'Where encrypted voice notes are uploaded. Tried from top to bottom, the next one is used when a server fails.',
                  servers: servers,
                  defaults: BlossomDefaults.servers,
                  addLabel: 'Add file server',
                  hint: 'files.example.com',
                  fileServer: true,
                  onSubmit: servers.length < ListLimits.blossomMax ? BlossomServers.add : null,
                  onRemove: (url) => _remove(context, url),
                ),
                const SizedBox(height: 20),
                Text(
                  'A new server gets a small test file before it is added. Files are encrypted before they leave your phone, so a server sees only scrambled data, its size, the time and your IP address.',
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
