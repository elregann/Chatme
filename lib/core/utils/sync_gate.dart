// lib/core/utils/sync_gate.dart
//
// Marks the "initial sync" window during which the app is pulling a large
// backlog from the relays: an account restore, the first login on a fresh
// install, or a restore that was interrupted by an app kill.
//
// While the gate is active:
//  - chat notifications are suppressed (messages are still saved normally),
//  - unread badges are not incremented,
//  - the relay subscription window is widened to the full 30-day fallback
//    ("fresh window"), because a restored account has no local history to
//    compute a tighter `since` from.
//
// The state is persisted in the settings box so an interrupted restore
// resumes quietly after a cold start instead of spamming notifications for
// the remaining backlog. RelayManager ends the gate when every relay has
// finished its incoming subscription's stored-event replay (EOSE, CLOSED,
// disconnect, or a per-relay deadline), followed by a short tail that lets
// the event pipeline flush.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class SyncGate {
  SyncGate._();

  static const String _startedAtKey = 'initial_sync_started_at';
  static const String _freshWindowKey = 'initial_sync_fresh_window';

  /// Hard upper bound for an initial sync. The normal path (EOSE plus the
  /// short tail) ends the gate much sooner; this only protects against a
  /// stuck pipeline or a relay that keeps the connection busy forever.
  static const int maxDurationMs = 10 * 60 * 1000;

  /// A persisted gate older than this is considered stale and dropped.
  static const int _resumeWindowMs = maxDurationMs;

  static final ValueNotifier<bool> _activeNotifier = ValueNotifier<bool>(false);

  /// True while the initial backlog sync is running.
  static bool get isActive => _activeNotifier.value;

  /// Starts (or restarts) the gate. Must be called BEFORE
  /// RelayManager.connect() so the subscriptions are opened with the
  /// widened window.
  static void start(String reason) {
    try {
      final box = Hive.box('settings');
      box.put(_startedAtKey, DateTime.now().millisecondsSinceEpoch);
      box.put(_freshWindowKey, true);
    } catch (_) {}
    if (!_activeNotifier.value) {
      _activeNotifier.value = true;
      debugPrint('[SyncGate] Initial sync started ($reason)');
    }
  }

  /// Resumes a gate that was interrupted by an app kill. Called from
  /// RelayManager.connect() on every cold start.
  static void resumeIfPending() {
    if (_activeNotifier.value) return;
    try {
      final box = Hive.box('settings');
      final startedAt = box.get(_startedAtKey, defaultValue: 0) as int;
      if (startedAt == 0) return;

      final age = DateTime.now().millisecondsSinceEpoch - startedAt;
      if (age < 0 || age > _resumeWindowMs) {
        // Stale gate from long ago: drop it silently.
        box.delete(_startedAtKey);
        box.delete(_freshWindowKey);
        return;
      }

      _activeNotifier.value = true;
      debugPrint(
        '[SyncGate] Initial sync resumed '
        '(${(age / 1000).toStringAsFixed(0)}s after start)',
      );
    } catch (_) {}
  }

  /// Epoch millis when the current gate started, or 0 when it is inactive.
  /// Used to tell restored history (older than the start) apart from
  /// messages that arrive live while the gate is still open.
  static int get startedAtMs {
    try {
      return Hive.box('settings').get(_startedAtKey, defaultValue: 0) as int;
    } catch (_) {
      return 0;
    }
  }

  /// Time left before [maxDurationMs], measured from the persisted start.
  /// Resuming an interrupted restore must not give the hard cap a fresh
  /// window on top of the time the gate was already active.
  static int get remainingMs {
    final startedAt = startedAtMs;
    if (startedAt == 0) return maxDurationMs;
    final remaining =
        maxDurationMs - (DateTime.now().millisecondsSinceEpoch - startedAt);
    return remaining > 0 ? remaining : 0;
  }

  /// Ends the gate. Safe to call multiple times.
  static void finish(String reason) {
    var wasActive = _activeNotifier.value;
    try {
      final box = Hive.box('settings');
      wasActive = wasActive ||
          (box.get(_startedAtKey, defaultValue: 0) as int) != 0;
      box.delete(_startedAtKey);
      box.delete(_freshWindowKey);
    } catch (_) {}
    if (wasActive) {
      debugPrint('[SyncGate] Initial sync finished ($reason)');
    }
    _activeNotifier.value = false;
  }

  /// True while subscriptions should use the widened 30-day sync window
  /// instead of the latest-contact-time heuristic.
  static bool get useFreshWindow {
    try {
      return Hive.box('settings').get(_freshWindowKey, defaultValue: false) == true;
    } catch (_) {
      return false;
    }
  }

  /// For tests: resets the in-memory state. Pass [keepPersisted] to
  /// simulate an app restart that still finds the persisted gate flag
  /// (in-memory value gone, box value alive on "disk").
  @visibleForTesting
  static void resetForTest({bool keepPersisted = false}) {
    _activeNotifier.value = false;
    if (keepPersisted) return;
    try {
      final box = Hive.box('settings');
      box.delete(_startedAtKey);
      box.delete(_freshWindowKey);
    } catch (_) {}
  }
}
