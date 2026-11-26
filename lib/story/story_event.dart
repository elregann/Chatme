import '../core/crypto/nip17_file.dart';
import 'story_item.dart';

class StoryEvent {
  /// A retract is a story rumor carrying this tag instead of a file. It keeps
  /// the routing kind used by the existing inbox so no chat path changes.
  static const String deleteTag = 'story_delete';

  /// Story ids become local filenames, so only canonical event ids are safe.
  /// A seal signature proves who wrote a rumor, not that its chosen id is safe.
  static final RegExp _storyIdPattern = RegExp(r'^[0-9a-f]{64}$');

  static bool isValidStoryId(String id) => _storyIdPattern.hasMatch(id);

  static List<List<String>> buildDeleteTags({
    required String receiverPubkey,
    required String storyId,
    required int expiresAtMs,
  }) {
    return [
      ['p', receiverPubkey],
      [deleteTag, storyId],
      ['expiration', '${expiresAtMs ~/ 1000}'],
    ];
  }

  static String? deleteIdFromTags(List<List<String>> tags) {
    for (final tag in tags) {
      if (tag.length > 1 &&
          tag[0] == deleteTag &&
          isValidStoryId(tag[1])) {
        return tag[1];
      }
    }
    return null;
  }

  static List<List<String>> buildViewReceiptTags({
    required String receiverPubkey,
    required String storyId,
  }) {
    return [
      ['p', receiverPubkey],
      ['e', storyId],
    ];
  }

  static String? storyViewIdFromTags(List<List<String>> tags) {
    for (final tag in tags) {
      if (tag.length > 1 && tag[0] == 'e' && isValidStoryId(tag[1])) {
        return tag[1];
      }
    }
    return null;
  }

  static List<List<String>> buildTags({
    required String receiverPubkey,
    required FileMessage file,
    required int expiresAtMs,
    String? caption,
  }) {
    final tags = <List<String>>[
      ['p', receiverPubkey],
      ['expiration', '${expiresAtMs ~/ 1000}'],
      ['story', '1'],
      ...file.rumorTags(receiver: receiverPubkey),
    ];
    if (caption != null && caption.trim().isNotEmpty) {
      tags.add(['caption', caption.trim()]);
    }
    return tags;
  }

  static StoryItem? fromRumor({
    required String rumorId,
    required String authorPubkey,
    required int createdAtMs,
    required List<List<String>> tags,
    required String content,
    String localPath = '',
  }) {
    if (!isValidStoryId(rumorId)) return null;

    String? getTag(String name) {
      for (final tag in tags) {
        if (tag.length > 1 && tag[0] == name) return tag[1];
      }
      return null;
    }

    final isStory = tags.any((t) => t.isNotEmpty && t[0] == 'story');
    if (!isStory) return null;

    final file = FileMessage.parse(content: content, tags: tags);
    if (file == null) return null;

    final expSec = int.tryParse(getTag('expiration') ?? '');
    final expiresAtMs = expSec != null
        ? expSec * 1000
        : createdAtMs + StoryItem.defaultDuration.inMilliseconds;
    final caption = getTag('caption') ?? '';

    return StoryItem(
      id: rumorId,
      authorPubkey: authorPubkey,
      createdAt: createdAtMs,
      expiresAt: expiresAtMs,
      mediaUrl: file.url,
      mimeType: file.mimeType,
      encryptionKey: file.key,
      encryptionNonce: file.nonce,
      fileHash: file.hash,
      originalHash: file.originalHash ?? '',
      caption: caption,
      width: file.width,
      height: file.height,
      durationSeconds: file.durationSeconds,
      size: file.plainSize ?? file.size,
      localPath: localPath,
    );
  }

}
