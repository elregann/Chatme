// media_storage.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// The private app folder that holds pictures, sent and received.
Future<Directory> mediaDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}media');
}

class MediaStorage {
  MediaStorage._();
  static final MediaStorage instance = MediaStorage._();

  Future<Directory> dir(String name) async {
    final base = await mediaDirectory();
    final target = Directory('${base.path}${Platform.pathSeparator}$name');
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }
}
