// voice_storage.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// The private app folder that holds voice notes, sent and received.
Future<Directory> voiceDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}voice');
}
