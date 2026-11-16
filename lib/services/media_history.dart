// media_history.dart

import '../models/chat_message.dart';

/// Pictures of one chat, newest first.
List<ChatMessage> imagesNewestFirst(Iterable<ChatMessage> messages) {
  return messages.where((m) => m.isImage).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

/// Pictures and videos of one chat, newest first, for the media grid.
List<ChatMessage> mediaNewestFirst(Iterable<ChatMessage> messages) {
  return messages.where((m) => m.isImage || m.isVideo).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
}

/// The media the viewer can swipe through and where it starts.
///
/// Pictures and videos are one gallery, because the grid shows them together
/// and the counter above the viewer has to match that grid.
class ViewerSet {
  final List<String> paths;
  final int index;
  final List<ChatMessage> messages;

  const ViewerSet(this.paths, this.index, {this.messages = const []});
}

/// Only downloaded media is in the viewer, the same way a tile that still
/// needs a download cannot be opened. Returns null when the tapped item is not
/// one of them.
ViewerSet? viewerSetFor(List<ChatMessage> media, String tappedId) {
  final paths = <String>[];
  final messages = <ChatMessage>[];
  var index = -1;
  for (final m in media) {
    if (!m.isImage && !m.isVideo) continue;
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
