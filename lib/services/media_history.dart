// media_history.dart

import '../models/chat_message.dart';

/// Pictures of one chat, newest first.
List<ChatMessage> imagesNewestFirst(Iterable<ChatMessage> messages) {
  return messages.where((m) => m.isImage).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

/// The pictures the viewer can swipe through and where it starts.
class ViewerSet {
  final List<String> paths;
  final int index;
  final List<ChatMessage> messages;

  const ViewerSet(this.paths, this.index, {this.messages = const []});
}

/// Only downloaded pictures are in the viewer. Returns null when the tapped
/// picture is not one of them.
ViewerSet? viewerSetFor(List<ChatMessage> images, String tappedId) {
  final paths = <String>[];
  final messages = <ChatMessage>[];
  var index = -1;
  for (final m in images) {
    if (m.localPath.isEmpty) continue;
    if (m.id == tappedId) index = paths.length;
    paths.add(m.localPath);
    messages.add(m);
  }
  if (index == -1) return null;
  return ViewerSet(paths, index, messages: messages);
}

/// "2 / 5"
String viewerCounter(int index, int total) => '${index + 1} / $total';
