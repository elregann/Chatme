import '../core/crypto/nip17_file.dart';
import 'story_item.dart';

class StoryEvent {
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
