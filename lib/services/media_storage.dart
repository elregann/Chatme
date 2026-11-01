// media_storage.dart

import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// The private app folder that holds pictures, sent and received.
Future<Directory> mediaDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}media');
}
