// voice_download.dart

import '../chat_manager.dart';
import '../models/chat_message.dart';
import 'file_transfer_service.dart';
import 'voice_storage.dart';

/// Downloads and decrypts a received voice note, remembers where it was saved
/// and returns that path.
Future<String> downloadVoiceNote(ChatMessage message) async {
  final file = message.fileMessage;
  if (file == null) throw const FileTransferException('download failed');
  final path = await FileTransferService.downloadAndSave(
    file,
    directory: await voiceDirectory(),
  );
  await ChatManager.instance.setLocalPath(message.id, message.chatKey, path);
  return path;
}
