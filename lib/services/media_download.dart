// media_download.dart

import '../chat_manager.dart';
import '../models/chat_message.dart';
import 'app_settings.dart';
import 'gallery_save.dart';
import 'file_transfer_service.dart';
import 'media_storage.dart';

/// Downloads and decrypts a received picture, remembers where it was saved
/// and returns that path.
Future<String> downloadImage(ChatMessage message) async {
  final file = message.fileMessage;
  if (file == null) throw const FileTransferException('download failed');
  final path = await FileTransferService.downloadAndSave(
    file,
    directory: await mediaDirectory(),
  );
  await ChatManager.instance.setLocalPath(message.id, message.chatKey, path);
  await GallerySaver.saveIfWanted(
    enabled: AppSettings.instance.saveToGalleryEnabled,
    received: !message.isMe,
    path: path,
  );
  return path;
}
