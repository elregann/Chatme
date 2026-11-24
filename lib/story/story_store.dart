import 'package:hive_flutter/hive_flutter.dart';

import 'story_item.dart';

class StoryStore {
  static const String boxName = 'stories';

  Box<Map> get _box => Hive.box<Map>(boxName);

  List<StoryItem> all({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final items = <StoryItem>[];
    for (final raw in _box.values) {
      try {
        final item = StoryItem.fromMap(Map<dynamic, dynamic>.from(raw));
        if (item.id.isEmpty || item.authorPubkey.isEmpty) continue;
        if (item.isExpiredAt(now)) continue;
        items.add(item);
      } catch (_) {}
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<StoryItem> byAuthor(String pubkey, {int? nowMs}) {
    return all(nowMs: nowMs)
        .where((item) => item.authorPubkey == pubkey)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  StoryItem? getById(String id, {int? nowMs}) {
    final raw = _box.get(id);
    if (raw == null) return null;
    try {
      final item = StoryItem.fromMap(Map<dynamic, dynamic>.from(raw));
      if (nowMs != null && item.isExpiredAt(nowMs)) return null;
      return item;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(StoryItem item) async {
    await _box.put(item.id, item.toMap());
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  Future<void> markViewed(String storyId, String viewerPubkey, int nowMs) async {
    final item = getById(storyId);
    if (item == null) return;
    if (item.viewedBy.containsKey(viewerPubkey)) return;
    final viewedBy = Map<String, int>.from(item.viewedBy);
    viewedBy[viewerPubkey] = nowMs;
    await put(item.copyWith(viewedBy: viewedBy));
  }

  Future<List<StoryItem>> purgeExpired({int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final expired = <StoryItem>[];
    final keys = _box.keys.toList();
    for (final key in keys) {
      final raw = _box.get(key);
      if (raw == null) continue;
      try {
        final item = StoryItem.fromMap(Map<dynamic, dynamic>.from(raw));
        if (!item.isExpiredAt(now)) continue;
        expired.add(item);
        await _box.delete(key);
      } catch (_) {
        await _box.delete(key);
      }
    }
    return expired;
  }
}
