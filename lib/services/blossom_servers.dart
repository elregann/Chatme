// blossom_servers.dart

import 'app_settings.dart';
import 'blossom_service.dart';
import 'server_lists.dart';

/// Adds [input] to [current] after a test upload to it worked. A bad address,
/// a duplicate or a full list is refused without contacting the server.
Future<ListEdit> addBlossomServer(
  List<String> current,
  String input, {
  required Future<void> Function(String url) probe,
}) async {
  final edit = ServerLists.add(
    current,
    input,
    normalize: ServerAddress.blossom,
    max: ListLimits.blossomMax,
  );
  if (!edit.ok) return edit;

  try {
    await probe(edit.list.last);
  } on BlossomException {
    return ListEdit(ListChange.unreachable, current);
  }
  return edit;
}

/// The file server list in settings, as the screen edits it.
class BlossomServers {
  BlossomServers._();

  static Future<ListEdit> add(String input) async {
    final settings = AppSettings.instance;
    final edit = await addBlossomServer(
      settings.blossomServers,
      input,
      probe: BlossomService.testUpload,
    );
    if (edit.ok) await settings.setBlossomServers(edit.list);
    return edit;
  }

  static Future<ListEdit> remove(String url) async {
    final settings = AppSettings.instance;
    final edit = ServerLists.remove(
      settings.blossomServers,
      url,
      minimum: ListLimits.blossomMin,
    );
    if (edit.ok) await settings.setBlossomServers(edit.list);
    return edit;
  }

  static Future<void> reset() {
    return AppSettings.instance.setBlossomServers(List.of(BlossomDefaults.servers));
  }
}
