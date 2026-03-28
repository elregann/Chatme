import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

const _taskName = 'nostr_reconnect';
const _taskTag = 'com.pribadi.chatme.reconnect';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    return Future.value(true);
  });
}

class BackgroundService {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    await Workmanager().initialize(
      callbackDispatcher,
    );
  }

  static Future<void> registerReconnectTask() async {
    if (kIsWeb) return;
    await Workmanager().registerPeriodicTask(
      _taskTag,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}