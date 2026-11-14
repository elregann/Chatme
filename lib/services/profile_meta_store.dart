// profile_meta_store.dart

import 'dart:async';
import 'package:hive/hive.dart';

/// Persisted ordering metadata for kind-0 profile events.
///
/// Kind 0 is a Nostr replaceable event: only the newest event for a pubkey
/// may change the profile. Keeping the winning timestamp and event id in Hive
/// makes that rule survive an app restart, so a relay replaying an older
/// profile cannot overwrite a newer one (and cannot flash a stale name or
/// picture on launch).
class ProfileMetaStore {
  ProfileMetaStore._();

  static final Map<String, _Kind0Meta> _cache = {};
  static StreamSubscription<BoxEvent>? _contactsSubscription;

  static Box? get _box =>
      Hive.isBoxOpen('profile_meta') ? Hive.box('profile_meta') : null;

  static _Kind0Meta _metaFor(String pubkey) {
    final cached = _cache[pubkey];
    if (cached != null) return cached;

    final box = _box;
    if (box != null) {
      try {
        final stored = box.get(pubkey);
        if (stored is Map) {
          final timestamp = stored['ts'];
          final eventId = stored['id'];
          final meta = _Kind0Meta(
            timestamp: timestamp is int ? timestamp : 0,
            eventId: eventId is String ? eventId : '',
          );
          _cache[pubkey] = meta;
          return meta;
        }
      } catch (_) {}
    }

    const empty = _Kind0Meta(timestamp: 0, eventId: '');
    _cache[pubkey] = empty;
    return empty;
  }

  /// True once any kind-0 has been processed for [pubkey].
  static bool hasProfile(String pubkey) => _metaFor(pubkey).timestamp > 0;

  /// Returns true when an event with [createdAt] and [eventId] should become
  /// the new winner for [pubkey].
  ///
  /// Older events are rejected. For equal timestamps NIP-01 keeps the event
  /// with the lowest id, and a replay of the same id is rejected so its side
  /// effects never run twice.
  static bool shouldAccept(String pubkey, int createdAt, String eventId) {
    final current = _metaFor(pubkey);
    if (createdAt > current.timestamp) return true;
    if (createdAt < current.timestamp) return false;
    if (eventId.isEmpty || eventId == current.eventId) return false;
    if (current.eventId.isEmpty) return true;
    return eventId.compareTo(current.eventId) < 0;
  }

  /// True while [createdAt] and [eventId] are still the winning event.
  static bool isCurrent(String pubkey, int createdAt, String eventId) {
    final current = _metaFor(pubkey);
    return current.timestamp == createdAt && current.eventId == eventId;
  }

  /// Drops the in-memory cache. Tests only.
  static void resetForTest() {
    _cache.clear();
  }

  /// Clears [pubkey] from the in-memory cache and the persisted box.
  ///
  /// The cache entry is removed synchronously so the next kind-0 for this
  /// pubkey is accepted even if the Hive delete is still in flight.
  static Future<void> forget(String pubkey) {
    _cache.remove(pubkey);

    final box = _box;
    if (box == null) return Future<void>.value();
    try {
      return box.delete(pubkey).catchError((Object _) {});
    } catch (_) {
      return Future<void>.value();
    }
  }

  /// Forgets the profile of every contact row deleted from [box].
  ///
  /// Contact rows are created from several flows, so watching the box keeps
  /// the profile cache in sync with every deletion path without each caller
  /// having to remember it.
  static void watchContactDeletions(Box box) {
    _contactsSubscription?.cancel();
    _contactsSubscription = box.watch().listen((event) {
      if (!event.deleted) return;
      final key = event.key;
      if (key is String) forget(key);
    });
  }

  /// Stops the contacts box watcher started by [watchContactDeletions].
  static Future<void> stopWatchingContactDeletions() async {
    final subscription = _contactsSubscription;
    _contactsSubscription = null;
    await subscription?.cancel();
  }

  /// Records [createdAt] and [eventId] as the winner for [pubkey].
  ///
  /// The in-memory guard is updated synchronously, before the returned future
  /// yields, so an echo arriving from another relay cannot race it. The Hive
  /// write is best effort: a failure only loses the cross-restart guard.
  static Future<void> remember(
    String pubkey,
    int createdAt,
    String eventId,
  ) {
    _cache[pubkey] = _Kind0Meta(timestamp: createdAt, eventId: eventId);

    final box = _box;
    if (box == null) return Future<void>.value();
    try {
      return box.put(pubkey, <String, dynamic>{
        'ts': createdAt,
        'id': eventId
      }).catchError((Object _) {});
    } catch (_) {
      return Future<void>.value();
    }
  }
}

class _Kind0Meta {
  final int timestamp;
  final String eventId;

  const _Kind0Meta({required this.timestamp, required this.eventId});
}
