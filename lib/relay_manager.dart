// relay_manager.dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'notification_handler.dart';
import 'call_manager.dart';
import 'call.dart';
import 'main.dart';
import 'chat_manager.dart';
import 'core/crypto/nip04.dart';
import 'core/crypto/nip17.dart';
import 'core/crypto/nip17_isolate.dart';
import 'core/crypto/nip17_file.dart';
import 'core/crypto/nostr_protocol.dart';
import 'core/utils/debug_logger.dart';
import 'core/utils/shortcut_helper.dart';
import 'core/utils/sync_gate.dart';
import 'services/app_settings.dart';
import 'services/file_send_service.dart';
import 'services/nostr_service.dart';
import 'models/chat_message.dart';
import 'models/contact.dart';
import 'services/server_lists.dart';

class RelayManager {
  Function? onMessageReceived;
  Function(String peerPubkey)? onIncomingMessageSaved;
  String? currentlyChattingWith;

  Function(Map<String, dynamic>)? onSignalReceived;

  /// Every relay we connect to: the inbox relays, then the others. The user
  /// edits both lists in the relay screen, see [RelayDefaults] for the start.
  List<String> get relays => AppSettings.instance.allRelays;

  /// Relays announced in our NIP-17 kind 10050 event. Other clients send our
  /// DMs to these relays, and some refuse to message us without the event.
  /// The spec recommends keeping the list small (1 to 3 relays).
  static List<String> get dmInboxRelays => AppSettings.instance.inboxRelays;

  /// Changes every time the relay lists change, for screens that show them.
  final ValueNotifier<int> relayListVersion = ValueNotifier(0);

  String? _dmRelayListEventId;
  final Set<String> _dmRelayListAcks = {};
  DateTime? _lastDmRelayListAttempt;
  int _dmRelayListAttempts = 0;
  Timer? _dmRelayListRetryTimer;

  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, bool> _connectionStatus = {};
  final Map<String, int> _reconnectAttempts = {};
  final Set<String> _reconnectScheduled = {};
  final Set<String> _processedEventIds = {};

  /// Relays that completed NIP-42 AUTH (confirmed by OK true).
  final Set<String> _authenticatedRelays = {};

  /// Challenges already answered this connection (prevents double-sign).
  final Set<String> _answeredAuthChallenges = {};

  /// AUTH event id → relayUrl, waiting for OK confirmation.
  final Map<String, String> _pendingAuthEventIds = {};

  /// In-flight guard: event IDs currently being processed (not yet
  /// finished). Prevents a race condition where the same event arrives
  /// from multiple relays within a window of under 2 seconds, before
  /// `_processedEventIds` has a chance to be populated.
  final Set<String> _inFlightEventIds = {};

  Timer? _cleanupTimer;
  Timer? _queueTimer;
  String? _subscriptionId;
  final ValueNotifier<bool> _isConnected = ValueNotifier(false);
  final ValueNotifier<int> _connectedCount = ValueNotifier(0);
  Map<String, bool> get connectionStatus => Map.unmodifiable(_connectionStatus);
  bool _isInitialized = false;
  bool _isConnecting = false;
  bool _isProcessingQueue = false;
  bool _isProcessingReactions = false;
  final Map<String, List<String>> _reactionAcks = {};
  final Map<String, int> _lastReactionAttempt = {};
  final Map<String, int> _reactionTimestamps = {};
  Timer? _reactionRetryTimer;
  int _reactionRetryCount = 0;
  final Map<String, int> _lastKind0Timestamp = {};

  /// Timestamp (ms) of the last re-send attempt per message ID.
  /// Prevents the offline queue from hammering the same message every tick.
  final Map<String, int> _lastQueueAttempt = {};

  // --- Incoming event pipeline --------------------------------------------
  // Relay bursts (account restore, cold start after downtime) deliver many
  // events at once. Events are queued and drained in small batches: the
  // NIP-17 unwrap runs in ONE isolate call per batch instead of one spawn
  // per message, and Hive/contacts/UI writes are flushed once per batch.
  final List<Map<String, dynamic>> _eventQueue = [];
  bool _isDrainingEvents = false;
  static const int _maxEventBatch = 16;

  // Contact rows buffered during a drain; written once per batch.
  final Map<String, Contact> _contactBuffer = {};
  final Set<String> _bufferedNewContacts = {};
  final Set<String> _drainSavedPeers = {};
  final Set<String> _drainTouchedChats = {};

  // --- Initial sync gate (restore / first login) ---------------------------
  // EOSE is per subscription, so the gate only waits for the `_incoming`
  // REQ: that is the one carrying messages we may notify about. A relay
  // leaves this set on EOSE, a non-auth CLOSED, disconnect, or its own
  // deadline. A short tail then lets the batch pipeline finish flushing.
  final Set<String> _syncWaitingRelays = {};
  final Map<String, Timer> _syncRelayTimers = {};
  Timer? _syncTailTimer;
  Timer? _syncHardTimer;
  Timer? _syncStartupTimer;

  /// A relay that never sends EOSE (or CLOSED) is released after this.
  static const Duration _syncRelayDeadline = Duration(seconds: 30);

  /// Short grace period after the last relay finishes, so events already in
  /// flight and the remaining drain batches land before notifications come
  /// back.
  static const Duration _syncTailDelay = Duration(seconds: 3);

  /// Serializes outgoing call signals. Wrapping now runs on a background
  /// isolate, so without this a later signal (e.g. hangup) could finish
  /// wrapping before an earlier one (e.g. offer) and be delivered out of order.
  Future<void> _callSignalSendChain = Future<void>.value();

  Function(Map<String, dynamic>)? onMessageReceivedWithData;
  Function(String)? onMessageDelivered;

  void connect() {
    if (_isConnecting || _isInitialized) return;
    try {
      _isConnecting = true;
      final myPubkey = AppSettings.instance.myPubkey;
      if (myPubkey.isEmpty) {
        _isConnecting = false;
        return;
      }
      _subscriptionId = 'chatme_${DateTime.now().millisecondsSinceEpoch}';
      _startCleanupTimer();

      if (_queueTimer == null || !_queueTimer!.isActive) {
        _queueTimer = Timer.periodic(const Duration(seconds: 15), (t) {
          if (_isConnected.value) {
            _processOfflineQueue();
          }
        });
      }

      // Pick up an interrupted restore (persisted gate flag). While the
      // gate is active the window is widened too: a restored account has
      // no local contact history yet, so `since` falls back to the full
      // 30-day window instead of trusting the previous account's chats.
      SyncGate.resumeIfPending();
      if (SyncGate.isActive) _startInitialSyncTracking();
      final int latestTime =
          SyncGate.useFreshWindow ? 0 : _computeLatestContactTime();

      final urls = relays;
      for (var i = 0; i < urls.length; i++) {
        Future.delayed(Duration(milliseconds: i * 300), () {
          _connectToRelay(urls[i], myPubkey, latestTime);
        });
      }

      // Safety net for the case where no incoming subscription is ever sent
      // (no relays configured, or every connect attempt fails before REQ).
      // Without this the gate would sit idle until the hard cap.
      if (SyncGate.isActive) {
        if (urls.isEmpty) {
          _finishInitialSync('no relays');
        } else {
          _syncStartupTimer?.cancel();
          _syncStartupTimer = Timer(
            Duration(milliseconds: urls.length * 300 + 5000),
            () {
              if (SyncGate.isActive && _syncWaitingRelays.isEmpty) {
                _finishInitialSync('no incoming subscriptions');
              }
            },
          );
        }
      }

      _isInitialized = true;
      _isConnecting = false;
    } catch (e) {
      _isConnecting = false;
    }
  }

  int _computeLatestContactTime() {
    int latestTime = 0;
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      for (var contact in contactsBox.values) {
        if (contact.lastChatTime > latestTime) {
          latestTime = contact.lastChatTime;
        }
      }
    } catch (_) {}
    return latestTime;
  }

  void disconnect() {
    _cleanupTimer?.cancel();
    _queueTimer?.cancel();
    _clearSyncTracking();
    _isProcessingQueue = false;

    for (var url in _connections.keys.toList()) {
      _closeConnection(url);
    }

    _connections.clear();
    _connectionStatus.clear();
    _reconnectAttempts.clear();
    _reconnectScheduled.clear();
    _authenticatedRelays.clear();
    _answeredAuthChallenges.clear();
    _pendingAuthEventIds.clear();
    _isInitialized = false;
    _isConnecting = false;
    _isConnected.value = false;
    _connectedCount.value = 0;
  }

  // ----------------------------------------------------------------- Gate

  /// Starts EOSE tracking for the active initial sync. Relays join as their
  /// subscriptions are sent. The hard timer is measured from the persisted
  /// start so resuming an interrupted restore cannot double the window.
  void _startInitialSyncTracking() {
    _clearSyncTracking();
    _syncHardTimer = Timer(
      Duration(milliseconds: SyncGate.remainingMs),
      () => _finishInitialSync('hard timeout'),
    );
    DebugLogger.log('[Sync] Initial sync tracking started');
  }

  /// Starts waiting for [relayUrl]'s `_incoming` EOSE. Called whenever the
  /// subscription is (re)sent, so an AUTH retry restarts its deadline.
  void _waitForIncomingEose(String relayUrl) {
    if (!SyncGate.isActive) return;
    _syncStartupTimer?.cancel();
    _syncStartupTimer = null;

    // A reconnect or late AUTH retry re-opens a relay: cancel a tail that
    // was already counting down.
    _syncTailTimer?.cancel();
    _syncTailTimer = null;

    _syncWaitingRelays.add(relayUrl);
    _syncRelayTimers.remove(relayUrl)?.cancel();
    _syncRelayTimers[relayUrl] = Timer(_syncRelayDeadline, () {
      _syncRelayTimers.remove(relayUrl);
      _onIncomingSyncDone(relayUrl, 'deadline');
    });
  }

  /// Releases a relay from the gate. Also used for relays that were never
  /// waiting (e.g. a connection error before the REQ was sent).
  void _onIncomingSyncDone(String relayUrl, String reason) {
    if (!SyncGate.isActive) return;
    _syncRelayTimers.remove(relayUrl)?.cancel();
    if (!_syncWaitingRelays.remove(relayUrl)) return;
    DebugLogger.log('[Sync] Incoming sync done: $relayUrl ($reason)');
    if (_syncWaitingRelays.isEmpty) _scheduleSyncTail();
  }

  /// Subscription ID that carries messages addressed to us. Only this REQ
  /// participates in the notification gate; our own events and kind 0
  /// profiles must not end it.
  String? get _incomingSubscriptionId =>
      _subscriptionId == null ? null : '${_subscriptionId}_incoming';

  void _onRelayEose(String relayUrl, String subId) {
    if (!SyncGate.isActive) return;
    if (subId != _incomingSubscriptionId) return;
    _onIncomingSyncDone(relayUrl, 'EOSE');
  }

  void _scheduleSyncTail() {
    _syncTailTimer?.cancel();
    _syncTailTimer = Timer(_syncTailDelay, () {
      // EOSE can arrive before the batch pipeline has finished writing the
      // backlog it already received. Keep the gate closed while the queue
      // or the drain is still busy.
      if (_eventQueue.isNotEmpty || _isDrainingEvents) {
        _scheduleSyncTail();
        return;
      }
      _finishInitialSync('all relays finished incoming sync');
    });
  }

  /// Message activity extends the tail only once every relay is done. Before
  /// that the relay state owns the gate; a busy stream must not keep
  /// notifications suppressed until the hard cap.
  void _noteSyncActivity() {
    if (!SyncGate.isActive) return;
    if (_syncWaitingRelays.isNotEmpty) return;
    final tail = _syncTailTimer;
    if (tail == null || !tail.isActive) return;
    _scheduleSyncTail();
  }

  void _finishInitialSync(String reason) {
    _clearSyncTracking();
    if (!SyncGate.isActive) return;
    SyncGate.finish(reason);
  }

  void _clearSyncTracking() {
    _syncTailTimer?.cancel();
    _syncHardTimer?.cancel();
    _syncStartupTimer?.cancel();
    for (final timer in _syncRelayTimers.values) {
      timer.cancel();
    }
    _syncRelayTimers.clear();
    _syncTailTimer = null;
    _syncHardTimer = null;
    _syncStartupTimer = null;
    _syncWaitingRelays.clear();
  }

  Future<void> _connectToRelay(String relayUrl, String myPubkey, int latestTime) async {
    try {
      _closeConnection(relayUrl);
      _authenticatedRelays.remove(relayUrl);
      _pendingAuthEventIds.removeWhere((_, u) => u == relayUrl);

      final channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      _connections[relayUrl] = channel;

      channel.ready.then((_) {}, onError: (e) {
        if (_connections[relayUrl] == channel) {
          _handleError(relayUrl, e);
        }
      });

      // Listen first so AUTH challenges are never missed.
      channel.stream.listen(
            (data) {
          _connectionStatus[relayUrl] = true;
          _updateConnectionStatus();
          _handleData(data, relayUrl);
        },
        onError: (e) {
          if (_connections[relayUrl] == channel) {
            _handleError(relayUrl, e);
          }
        },
        onDone: () {
          if (_connections[relayUrl] == channel) {
            _handleDisconnect(relayUrl);
          }
        },
        cancelOnError: true,
      );

      // Send REQs immediately. AUTH-required relays will CLOSED them;
      // we re-send after AUTH is confirmed via OK.
      _sendSubscriptions(relayUrl, myPubkey, latestTime);

      // No application-level PING — NIP-01 does not define it.
      // Keep-alive is handled by the WebSocket layer / normal traffic.

      _connectionStatus[relayUrl] = true;
      _updateConnectionStatus();
      DebugLogger.log('[Relay] Connected: $relayUrl');

      Future.delayed(const Duration(seconds: 10), () {
        if (_connections[relayUrl] == channel &&
            _connectionStatus[relayUrl] == true) {
          _reconnectAttempts[relayUrl] = 0;
        }
      });
    } catch (e) {
      DebugLogger.log('[Relay] Connection failed: $relayUrl | $e', type: 'ERROR');
      _handleError(relayUrl, e);
    }
  }

  /// Build and send the three core subscriptions for a relay.
  /// Safe to call multiple times (e.g. after successful NIP-42 AUTH).
  void _sendSubscriptions(String relayUrl, String myPubkey, int latestTime) {
    final channel = _connections[relayUrl];
    if (channel == null) return;

    // While the initial sync gate is open, every subscribed relay owes us
    // an EOSE for its `_incoming` request before notifications may come
    // back to life.
    if (SyncGate.isActive) _waitForIncomingEose(relayUrl);

    final nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int syncSince = nowTimestamp - 2592000; // fallback 30 days

    if (latestTime > 0) {
      final computed = (latestTime ~/ 1000) - 3600;
      // NIP-59 randomises gift-wrap `created_at` up to 2 days into the past.
      // Always look back at least 3 days.
      final minimum = nowTimestamp - 259200; // 3 days
      syncSince = computed < minimum ? computed : minimum;
      DebugLogger.log(
        '[Sync] $relayUrl since ${DateTime.fromMillisecondsSinceEpoch(syncSince * 1000)}',
      );
    }

    // Keep kind 1 for mentions/reactions context, 4 for legacy, 7 reactions, 1059 gift-wrap.
    final List<int> neededKinds = [1, 4, 7, 1059];

    final subToMe = jsonEncode([
      "REQ",
      "${_subscriptionId!}_incoming",
      {
        "kinds": neededKinds,
        "#p": [myPubkey],
        "since": syncSince,
      }
    ]);

    final subFromMe = jsonEncode([
      "REQ",
      "${_subscriptionId!}_outgoing",
      {
        "kinds": neededKinds,
        "authors": [myPubkey],
        "since": syncSince,
      }
    ]);

    channel.sink.add(subToMe);
    channel.sink.add(subFromMe);

    // Profiles of known contacts + ourselves.
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final authorList = <String>[
        ...contactsBox.keys.map((k) => k.toString()),
        myPubkey,
      ];

      final subProfiles = jsonEncode([
        "REQ",
        "${_subscriptionId!}_profiles",
        {
          "kinds": [0],
          "authors": authorList,
        }
      ]);
      channel.sink.add(subProfiles);
    } catch (e) {
      DebugLogger.log('[Relay] Profile sub failed on $relayUrl | $e', type: 'ERROR');
    }
  }

  void _closeConnection(String url) {
    try {
      _connections[url]?.sink.close();
      _connections.remove(url);
      _connectionStatus.remove(url);
      _authenticatedRelays.remove(url);
      _pendingAuthEventIds.removeWhere((_, u) => u == url);
    } catch (e) {
      DebugLogger.log('[Relay] Close connection error | $e', type: 'ERROR');
    }
  }

  Future<void> _handleData(dynamic data, String url) async {
    try {
      final message = data.toString();

      final decoded = jsonDecode(message);
      if (decoded is! List || decoded.isEmpty) return;

      final type = decoded[0];

      // ["EOSE", <subId>] — the relay finished replaying stored events for
      // that subscription. (The old raw substring check also swallowed any
      // chat message that literally contained "EOSE" — decoding first fixes
      // that.)
      if (type == "EOSE" && decoded.length >= 2) {
        _onRelayEose(url, decoded[1].toString());
        return;
      }

      // ["AUTH", "<challenge>"]
      if (type == "AUTH" && decoded.length >= 2) {
        await _handleAuthChallenge(url, decoded[1].toString());
        return;
      }

      // ["CLOSED", <subId>, <reason?>]
      if (type == "CLOSED" && decoded.length >= 2) {
        final subId = decoded[1].toString();
        final reason = decoded.length >= 3 ? decoded[2].toString() : '';
        DebugLogger.log('[Relay] CLOSED $subId on $url | $reason');

        // Only re-sub after AUTH is *confirmed* (OK true). Do not re-sub
        // while AUTH is still pending — that causes the loop you saw.
        final lower = reason.toLowerCase();
        final isAuthRequired = lower.contains('auth-required');

        // A relay that refuses or kills the incoming subscription will
        // never send its EOSE. Treat it as finished for the gate, unless
        // we are about to retry it after AUTH.
        if (SyncGate.isActive &&
            !isAuthRequired &&
            subId == _incomingSubscriptionId) {
          _onIncomingSyncDone(url, 'CLOSED');
        }

        if (isAuthRequired &&
            _authenticatedRelays.contains(url) &&
            !_pendingAuthEventIds.values.contains(url)) {
          final myPubkey = AppSettings.instance.myPubkey;
          if (myPubkey.isNotEmpty) {
            _sendSubscriptions(url, myPubkey, _computeLatestContactTime());
          }
        }
        return;
      }

      if (type == "NOTICE" && decoded.length >= 2) {
        DebugLogger.log('[Relay] NOTICE on $url | ${decoded[1]}');
        return;
      }

      if (decoded.length > 2) {
        if (type == "EVENT") await _handleEvent(decoded, url);
        if (type == "OK") _handleOk(decoded, url);
      }
    } catch (e) {
      DebugLogger.log('[Relay] Data handling error | $e', type: 'ERROR');
    }
  }

  /// Sign and send kind-22242 AUTH response. Wait for OK before re-subscribing.
  Future<void> _handleAuthChallenge(String relayUrl, String challenge) async {
    final challengeKey = '$relayUrl::$challenge';
    if (_answeredAuthChallenges.contains(challengeKey)) return;
    _answeredAuthChallenges.add(challengeKey);

    final myPubkey = AppSettings.instance.myPubkey;
    final myPrivkey = AppSettings.instance.myPrivkey;
    if (myPubkey.isEmpty || myPrivkey.isEmpty) {
      DebugLogger.log('[AUTH] Missing keys on $relayUrl', type: 'ERROR');
      return;
    }

    final channel = _connections[relayUrl];
    if (channel == null) return;

    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // NIP-42 example uses trailing slash on relay URL.
      final relayTag = relayUrl.endsWith('/') ? relayUrl : '$relayUrl/';

      final unsignedEvent = {
        'kind': 22242,
        'pubkey': myPubkey,
        'created_at': now,
        'tags': [
          ['relay', relayTag],
          ['challenge', challenge],
        ],
        'content': '',
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);
      final signature = NostrSigner.sign(eventId, myPrivkey);
      final signedEvent = {
        ...unsignedEvent,
        'id': eventId,
        'sig': signature,
      };

      _pendingAuthEventIds[eventId] = relayUrl;
      channel.sink.add(jsonEncode(["AUTH", signedEvent]));
      DebugLogger.log('[AUTH] Sent challenge response on $relayUrl (id=$eventId)');
      // Do NOT re-sub here. Wait for ["OK", eventId, true, ...] in _handleOk.
    } catch (e) {
      DebugLogger.log('[AUTH] Failed on $relayUrl | $e', type: 'ERROR');
      _answeredAuthChallenges.remove(challengeKey);
    }
  }

  Future<void> _handleEvent(List<dynamic> decoded, String url) async {
    if (decoded.length <= 2) return;

    final rawEvent = decoded[2];
    if (rawEvent is! Map) return;
    final event = rawEvent as Map<String, dynamic>;

    final eventId = event['id']?.toString() ?? '';
    final kind = event['kind'] is int ? event['kind'] as int : 0;
    final createdAt = event['created_at'] is int ? event['created_at'] as int : 0;

    // Cache profile picture from kind 0 events (only if it's newer)
    if (kind == 0) {
      final pubkey = event['pubkey'] is String ? event['pubkey'] as String : null;
      if (pubkey != null) {
        try {
          final rawContent = event['content'];
          if (rawContent is String && rawContent.trim().startsWith('{')) {
            final content = jsonDecode(rawContent);
            if (content is Map<String, dynamic>) {
              final picture = content['picture'] is String ? content['picture'] as String : null;

              final lastProcessed = _lastKind0Timestamp[pubkey] ?? 0;
              if (createdAt >= lastProcessed) {
                _lastKind0Timestamp[pubkey] = createdAt;

                final oldPicture = _profilePics.containsKey(pubkey) ? _profilePics.get(pubkey) : null;
                final hasPictureChanged = oldPicture != picture;

                if (picture != null && picture.isNotEmpty) {
                  _profilePics.put(pubkey, picture);
                } else {
                  _profilePics.delete(pubkey);
                }

                if (hasPictureChanged) {
                  UserAvatar.invalidate(pubkey);
                }
                _resolveProfileWaiters(pubkey, picture);

                // If this is our own profile, keep AppSettings in sync too.
                if (pubkey == AppSettings.instance.myPubkey) {
                  if (picture != null && picture.isNotEmpty) {
                    AppSettings.instance.savePhotoUrl(picture);
                  } else {
                    AppSettings.instance.savePhotoUrl('');
                  }
                }

                final name = content['name'] is String ? content['name'] as String : null;
                final nip05 = content['nip05'] is String ? content['nip05'] as String : null;
                final hasValidName = name != null &&
                    name.isNotEmpty &&
                    !Contact.isPlaceholderName(name, pubkey);

                // Placeholder names (npub stubs etc., published by older
                // clients while their global ID was disconnected) are not a
                // real identity — never let them pollute the contact row.
                if (hasValidName) {
                  try {
                    final contactsBox = Hive.box<Contact>('contacts');
                    final contact = contactsBox.get(pubkey);
                    if (contact != null) {
                      var changed = false;

                      // The global ID is the contact's remote identity —
                      // always keep it fresh, but never let a locally saved
                      // nickname clobber it (it lives in its own field).
                      if (contact.globalId != name) {
                        contact.globalId = name;
                        changed = true;
                      }

                      // The display name only follows remote metadata while
                      // the user hasn't saved their own nickname yet.
                      if (!contact.isSaved && contact.name != name) {
                        contact.name = name;
                        changed = true;
                      }

                      if (changed) {
                        await contactsBox.put(pubkey, contact);

                        // Keep Android conversation shortcut label in sync with profile name
                        await ShortcutHelper.pushConversationShortcut(
                          id: pubkey,
                          name: contact.displayName,
                          avatarBytes: null,
                        );
                      }
                    }
                  } catch (_) {}
                }

                if (!hasValidName && (nip05 == null || nip05.isEmpty)) {
                  // A newer kind-0 with neither a name nor a nip05 is the
                  // signature of a released global ID (ChatMe's disconnect
                  // broadcast; old app versions published an npub stub in
                  // its place). Drop the cached identity so the row falls
                  // back to npub instead of showing a stale handle.
                  await AppSettings.clearContactIdentity(pubkey);
                }

                // Note: no manual onMessageReceived here. The UI already
                // rebuilds via Hive listeners (contacts box, profile_pics
                // box). Calling this 100x on startup caused a rebuild
                // storm that contributed to jank.
              }
            }
          }
        } catch (e) {
          DebugLogger.log('[Profile] Cache error | $e', type: 'ERROR');
        }
      }
    }

    if (eventId.isEmpty || _processedEventIds.contains(eventId)) return;

    // In-flight guard: if this event ID is currently being processed by
    // another caller (from a different relay), skip immediately. The
    // `add` below is synchronous — there is no `await` before it — so
    // there is no race window.
    if (_inFlightEventIds.contains(eventId)) return;
    _inFlightEventIds.add(eventId);

    // Queued events keep the guard until the drain is done with them, so
    // a duplicate copy arriving from another relay cannot enter the queue
    // as well.
    bool queued = false;

    try {
      // Persistent dedup: skip events already processed in a previous
      // session, BEFORE doing expensive NIP-17 unwrap. This is what
      // makes cold start fast after the first session.
      try {
        if (_processedEvents.containsKey(eventId)) {
          _processedEventIds.add(eventId);
          return;
        }
      } catch (_) {}

      // Anything that survives dedup counts as initial-sync activity; it
      // pushes the quiet-period safety net forward while a backlog is
      // still streaming in.
      _noteSyncActivity();

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final myPubkey = AppSettings.instance.myPubkey;
      final senderPubkey = event['pubkey']?.toString() ?? '';

      if (kind == 7) {
        // Read receipts are tiny and time-sensitive: handle them inline.
        if (senderPubkey == myPubkey || now - createdAt > 60) {
          _processedEventIds.add(eventId);
          return;
        }

        final bool success = await _handleReceiptEvent(event);
        if (success) {
          _processedEventIds.add(eventId);
          try {
            _processedEvents.put(eventId, DateTime.now().millisecondsSinceEpoch);
          } catch (_) {}
        }
        return;
      }

      if (kind == 1 || kind == 4 || kind == 1059) {
        // Message traffic goes through the batch pipeline: one isolate
        // call unwraps up to [_maxEventBatch] gift wraps, and
        // Hive/contact/UI writes are flushed once per batch instead of
        // once per message.
        _eventQueue.add(event);
        queued = true;
        _scheduleEventDrain();
      }
    } finally {
      if (!queued) _inFlightEventIds.remove(eventId);
    }
  }

  // ------------------------------------------------------------ Event queue

  /// Kicks off a drain on the next event-loop turn. Events arriving while
  /// a drain is already running are picked up by that drain's loop.
  void _scheduleEventDrain() {
    if (_isDrainingEvents) return;
    _isDrainingEvents = true;
    Future(() => _drainEvents());
  }

  /// Chronological order for a batch: the rumor timestamp when the gift
  /// wrap was already unwrapped (milliseconds), otherwise the event's
  /// `created_at` (converted to milliseconds).
  int _batchSortKey(Map<String, dynamic> event, Nip17Result? result) =>
      result?.timestamp ?? ((event['created_at'] as int? ?? 0) * 1000);

  Future<void> _drainEvents() async {
    try {
      while (_eventQueue.isNotEmpty) {
        final batch = _eventQueue.take(_maxEventBatch).toList();
        _eventQueue.removeRange(0, batch.length);

        // Unwrap every gift wrap of the batch in ONE isolate call. A
        // single null result only fails that one event; only a total
        // isolate failure (caught below) fails them all.
        final wrappedIndexes = <int>[
          for (var i = 0; i < batch.length; i++)
            if (batch[i]['kind'] == 1059) i
        ];
        final unwrapped = <int, Nip17Result?>{};
        if (wrappedIndexes.isNotEmpty) {
          List<Nip17Result?> results;
          try {
            results = await Nip17Isolate.unwrapBatch(
              giftWrapEvents: [
                for (final i in wrappedIndexes) batch[i],
              ],
              receiverPrivkey: AppSettings.instance.myPrivkey,
              receiverPubkey: AppSettings.instance.myPubkey,
            );
          } catch (e) {
            DebugLogger.log('[NIP-17] Batch unwrap failed | $e', type: 'ERROR');
            results = List<Nip17Result?>.filled(wrappedIndexes.length, null);
          }
          for (var j = 0; j < wrappedIndexes.length; j++) {
            unwrapped[wrappedIndexes[j]] = results[j];
          }
        }

        // Process in chronological order so reply previews resolve.
        final order = List<int>.generate(batch.length, (i) => i)
          ..sort((a, b) => _batchSortKey(batch[a], unwrapped[a])
              .compareTo(_batchSortKey(batch[b], unwrapped[b])));

        // Processing counts as sync activity too: a huge backlog keeps
        // draining long after the last event ARRIVED (and long after
        // EOSE), and the gate must stay closed until the queue is empty.
        _noteSyncActivity();

        var anyProcessed = false;
        for (final i in order) {
          final event = batch[i];
          final eventId = event['id']?.toString() ?? '';
          var success = false;
          try {
            success = await _processIncomingEvent(event, unwrapped[i]);
          } catch (e) {
            DebugLogger.log('[Message] Incoming event error | $e', type: 'ERROR');
          } finally {
            // Release the duplicate guard no matter the outcome; failures
            // are not marked processed, so another relay's copy can retry.
            _inFlightEventIds.remove(eventId);
          }
          if (success) {
            anyProcessed = true;
            _processedEventIds.add(eventId);
            try {
              _processedEvents.put(eventId, DateTime.now().millisecondsSinceEpoch);
            } catch (_) {}
          }
        }

        if (anyProcessed) await _flushDrainSideEffects();

        // Yield between batches so a fresh message or an incoming call
        // signal never waits behind a long backlog.
        await Future.delayed(Duration.zero);
      }
    } catch (e) {
      DebugLogger.log('[Sync] Event drain failed | $e', type: 'ERROR');
    } finally {
      _isDrainingEvents = false;
      // Events queued while the last batch was running must not sit idle
      // until the next EVENT arrives.
      if (_eventQueue.isNotEmpty) _scheduleEventDrain();
    }
  }

  /// Writes everything the batch deferred: the chat registry (one rebuild
  /// of the chat list per affected chat), buffered contact rows, and the
  /// UI callbacks (once per batch instead of once per message).
  Future<void> _flushDrainSideEffects() async {
    try {
      for (final chatKey in _drainTouchedChats) {
        await ChatManager.instance.repairPendingReplies(chatKey);
        await ChatManager.instance.touchChatRegistry(chatKey);
      }
      _drainTouchedChats.clear();

      await _flushContactBuffer();

      for (final peerPubkey in _drainSavedPeers) {
        onIncomingMessageSaved?.call(peerPubkey);
      }
      _drainSavedPeers.clear();

      onMessageReceived?.call();
    } catch (e) {
      DebugLogger.log('[Sync] Flush side effects failed | $e', type: 'ERROR');
    }
  }

  void _processCallSignal(Map<String, dynamic> event) {
    try {
      final rawContent = event['content'] as String?;
      if (rawContent == null || !rawContent.trim().startsWith('{')) return;
      final signalData = jsonDecode(rawContent);
      final callerPubkey = event['pubkey'];

      if (signalData['type'] == 'offer') {
        try {
          final declinedAt = Hive.box('settings')
              .get('declined_call_$callerPubkey', defaultValue: 0) as int;
          final offerMs = (event['created_at'] as int? ?? 0) * 1000;
          if (declinedAt > 0 && offerMs <= declinedAt) {
            DebugLogger.log('[Call] Offer ignored: already declined');
            return;
          }
        } catch (e) {
          debugPrint('[OfferCheck] error | $e');
        }

        String finalDisplayName = AppSettings.formatDisplayName(callerPubkey);
        try {
          final contactBox = Hive.box<Contact>('contacts');
          final savedContact = contactBox.get(callerPubkey);
          if (savedContact != null) {
            finalDisplayName = savedContact.displayName;
          }
        } catch (e) {
          DebugLogger.log('[Call] Failed to load contact | $e', type: 'ERROR');
        }

        final Color incomingPeerColor = Color(
            int.parse(callerPubkey.substring(0, 8), radix: 16) | 0xFF000000
        );

        CallManager.instance.setSessionInfo(
          finalDisplayName,
          callerPubkey,
          incomingPeerColor,
        );

        final cm = CallManager.instance;
        cm.currentCallDirection = CallType.incoming;

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final bool answeredFromNotification =
            cm.autoAnswerPubkey == callerPubkey &&
                nowMs - cm.autoAnswerAtMs < 40000;
        cm.autoAnswerPubkey = null;
        final bool openFromLaunch = cm.openCallScreenOnOffer &&
            nowMs - cm.openCallScreenAtMs < 40000;
        cm.openCallScreenOnOffer = false;

        if (answeredFromNotification && navigatorKey.currentContext != null) {
          NotificationHandler.cancelIncomingCall();
          CallScreenNavigator.showCallScreen(
            context: navigatorKey.currentContext!,
            peerName: finalDisplayName,
            peerPubkey: callerPubkey,
            isIncoming: true,
            relay: this,
            peerColor: incomingPeerColor,
            remoteSdp: signalData['data'],
            autoAccept: true,
          );
        } else if (openFromLaunch && navigatorKey.currentContext != null) {
          // Keep the call pending, so the notification buttons still work if the
          // user minimizes the call screen.
          cm.pendingIncoming = PendingIncomingCall(
            callerPubkey: callerPubkey,
            callerName: finalDisplayName,
            callerColor: incomingPeerColor,
            remoteSdp: signalData['data'],
          );
          if (cm.launchCallerPubkey == null) {
            // App was opened by the ringing notification: show the call screen.
            CallScreenNavigator.showCallScreen(
              context: navigatorKey.currentContext!,
              peerName: finalDisplayName,
              peerPubkey: callerPubkey,
              isIncoming: true,
              relay: this,
              peerColor: incomingPeerColor,
              remoteSdp: signalData['data'],
              autoAccept: false,
              closeAppWhenCallEnds: true,
            );
          }
        } else {
          cm.pendingIncoming = PendingIncomingCall(
            callerPubkey: callerPubkey,
            callerName: finalDisplayName,
            callerColor: incomingPeerColor,
            remoteSdp: signalData['data'],
          );
          cm.activePeerPubkey = callerPubkey;
          cm.activePeerName = finalDisplayName;
          cm.activePeerColor = incomingPeerColor;
          cm.currentCallDirection = CallType.incoming;

          if (CallScreenNavigator.openScreens == 0) {
            NotificationHandler.showIncomingCall(
              callerPubkey: callerPubkey,
              callerName: finalDisplayName,
            );
          }
        }
      } else if (signalData['type'] == 'answer') {
        CallManager.instance.handleAnswer(signalData['data'], () {});
      } else if (signalData['type'] == 'candidate') {
        CallManager.instance.addCandidate(signalData['data']);
      } else if (signalData['type'] == 'hangup') {
        CallManager.instance.pendingIncoming = null;
        NotificationHandler.cancelIncomingCall();
        CallManager.instance.stopCall();
      }
    } catch (e) {
      DebugLogger.log('[Call] Signal processing failed | $e', type: 'ERROR');
    }
  }

  /// Processes one queued event. [nip17Result] carries the precomputed
  /// unwrap for kind 1059 gift wraps (done per batch by [_drainEvents],
  /// not per message); `null` means that unwrap failed.
  Future<bool> _processIncomingEvent(
    Map<String, dynamic> event,
    Nip17Result? nip17Result,
  ) async {
    try {
      final eventId = event['id']?.toString() ?? '';
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      String decrypted = '';
      String actualSenderPubkey = '';
      int timestamp = (event['created_at'] as int? ?? 0) * 1000;
      String actualEventId = eventId;
      String peerPubkey = '';
      String receiverPubkey = '';
      List tags = event['tags'] as List? ?? [];
      String content = event['content']?.toString() ?? '';

      if (event['kind'] == 1059) {
        if (nip17Result == null) {
          DebugLogger.log('[NIP-17] Unwrap failed in batch | $eventId', type: 'ERROR');
          return false;
        }
        decrypted = nip17Result.plaintext;
        actualSenderPubkey = nip17Result.senderPubkey;
        timestamp = nip17Result.timestamp;
        actualEventId = nip17Result.rumorId;
        receiverPubkey = nip17Result.receiverPubkey;

        final bool isFromMe = (actualSenderPubkey == myPubkey);
        peerPubkey = isFromMe ? receiverPubkey : actualSenderPubkey;
      } else {
        actualSenderPubkey = event['pubkey']?.toString() ?? '';
        tags = event['tags'] as List? ?? [];
        receiverPubkey = _extractReceiverPubkey(tags);
        final bool isFromMe = (actualSenderPubkey == myPubkey);
        peerPubkey = isFromMe ? receiverPubkey : actualSenderPubkey;

        content = event['content']?.toString() ?? '';
        if (event['kind'] == 4) {
          decrypted = Nip04.decrypt(content, myPrivkey, peerPubkey);
        } else if (event['kind'] == 1) {
          decrypted = content;
        }
      }

      if (peerPubkey.isEmpty || peerPubkey == myPubkey) return true;

      if (nip17Result != null && nip17Result.rumorKind == Nip17.kindCallSignal) {
        try {
          final signalJson = nip17Result.plaintext;
          final signalData = jsonDecode(signalJson);
          if (signalData is Map) {
            final type = signalData['type']?.toString() ?? '';

            final ttlSec = type == 'offer' ? 30 : 60;
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final ageSec = (nowMs - timestamp) ~/ 1000;

            if (ageSec > ttlSec || ageSec < -60) {
              DebugLogger.log(
                '[Call] Stale CALL_SIGNAL ignored '
                    '(type=$type, age=${ageSec}s, ttl=${ttlSec}s)',
              );
              return true;
            }

            if ((type == 'answer' ||
                    type == 'candidate' ||
                    type == CallConstants.signalRestartOffer) &&
                CallManager.instance.callState == CallState.idle) {
              DebugLogger.log('[Call] Cold CALL_SIGNAL ignored (type=$type, no active call)');
              return true;
            }

            final syntheticEvent = {
              'pubkey': actualSenderPubkey,
              'content': signalJson,
              'created_at': timestamp ~/ 1000,
              'kind': 1059,
              'id': actualEventId,
            };

            if (onSignalReceived != null) {
              try {
                onSignalReceived!(syntheticEvent);
              } catch (e) {
                DebugLogger.log('[Call] onSignalReceived error | $e', type: 'ERROR');
              }
              return true;
            }

            if (actualSenderPubkey != myPubkey) {
              _processCallSignal(syntheticEvent);
            }
          }
        } catch (e) {
          DebugLogger.log('[Call] CALL_SIGNAL parse failed | $e', type: 'ERROR');
        }
        return true;
      }

      final chatKey = ChatManager.instance.getChatKey(myPubkey, peerPubkey);

      final bool preExisting = await ChatManager.instance.isMessageExists(actualEventId, chatKey);
      if (preExisting) return true;

      final settingsBox = Hive.box('settings');
      final int cutOffTime = settingsBox.get('cut_off_$peerPubkey', defaultValue: 0);

      if (timestamp <= cutOffTime) return true;

      if (decrypted.isEmpty) {
        decrypted = '[Encrypted Message]';
      }

      final bool isFromMe = (actualSenderPubkey == myPubkey);

      // Reaction (NIP-25)
      if (nip17Result != null && nip17Result.rumorKind == Nip17.kindReaction) {
        String? targetId;
        for (final t in nip17Result.rumorTags) {
          if (t.length > 1 && t[0] == 'e') targetId = t[1];
        }
        final emoji = _reactionEmojiFrom(nip17Result.plaintext);
        if (targetId == null || targetId.isEmpty || emoji == null) return true;
        return await _updateMessageReaction(targetId, actualSenderPubkey, emoji, chatKey);
      }

      // Read receipt (Chatme custom kind)
      if (nip17Result != null && nip17Result.rumorKind == Nip17.kindReadReceipt) {
        final targetMessageId = nip17Result.replyToId ?? '';
        final status = nip17Result.plaintext.trim();
        if (targetMessageId.isEmpty || status.isEmpty) return true;
        final bool applied = await ChatManager.instance.updateMessageStatus(
          targetMessageId,
          status,
          chatKey: chatKey,
        );
        if (applied) onMessageReceived?.call();
        return true;
      }

      // File message (NIP-17 kind 15), shown as a voice note or a file
      Map<String, String> fileMap = const {};
      if (nip17Result != null && nip17Result.rumorKind == Nip17.kindFile) {
        final fileMessage = FileMessage.parse(
          content: nip17Result.plaintext,
          tags: nip17Result.rumorTags,
        );
        if (fileMessage == null) return true;
        fileMap = fileMessage.toMap();
        decrypted = fileMessage.previewLabel;
      }

      // Regular chat message
      String? replyToId;
      if (event['kind'] == 1059 && nip17Result != null) {
        replyToId = nip17Result.replyToId;
      } else {
        for (var t in tags) {
          if (t is List && t.length > 1 && t[0] == 'e') {
            replyToId = t[1].toString();
            break;
          }
        }
      }

      String? replyToContent;
      String? replyToSenderPubkey;
      if (replyToId != null) {
        final originalMsg = await ChatManager.instance.getMessageById(replyToId, chatKey);
        replyToContent = originalMsg?.plaintext;
        replyToSenderPubkey = originalMsg?.senderPubkey;
      }

      final String initialStatus = isFromMe ? 'sending' : 'sent';

      final chatMessage = ChatMessage(
        id: actualEventId,
        senderPubkey: actualSenderPubkey,
        receiverPubkey: receiverPubkey.isEmpty ? peerPubkey : receiverPubkey,
        content: content,
        plaintext: decrypted,
        timestamp: timestamp,
        status: initialStatus,
        chatKey: chatKey,
        replyToId: replyToId,
        replyToContent: replyToContent,
        replyToSenderPubkey: replyToSenderPubkey,
        giftWrapId: eventId,
        file: fileMap,
      );

      // Defer the per-chat side effects (registry touch, reply repairs,
      // contact preview, callbacks) to the end of the batch — during a
      // 1000-message restore they would otherwise fire once per message.
      final bool newlySaved = await ChatManager.instance.saveMessage(
        chatMessage,
        touchChatList: false,
        updateContactPreview: false,
      );

      // If saveMessage only updated an existing entry (i.e. this is a
      // duplicate), or if the message is already marked as read, do not
      // increment the unread badge.
      final savedMsg = ChatManager.instance.getMessageByIdSync(actualEventId, chatKey);
      final bool isAlreadyRead = savedMsg?.status == 'read';
      final bool alreadyExistsActual = !newlySaved || isAlreadyRead;

      _drainTouchedChats.add(chatKey);
      _bufferContactUpdate(peerPubkey, decrypted, timestamp, isFromMe, alreadyExistsActual);

      if (newlySaved && !isFromMe) _drainSavedPeers.add(peerPubkey);
      return true;
    } catch (e) {
      DebugLogger.log('[Message] Incoming event error | $e', type: 'ERROR');
      return false;
    }
  }

  Future<bool> _handleReceiptEvent(Map<String, dynamic> event) async {
    try {
      final tags = event['tags'] as List? ?? [];
      final senderPubkey = event['pubkey']?.toString() ?? '';
      final myPubkey = AppSettings.instance.myPubkey;

      if (senderPubkey == myPubkey) return true;

      String? originalMessageId;
      String? targetP;
      bool isReadStatus = false;

      for (final t in tags) {
        if (t is List && t.length > 1) {
          if (t[0] == 'e') originalMessageId = t[1].toString();
          if (t[0] == 'p') targetP = t[1].toString();
          if (t[0] == 'status' && t[1] == 'read') isReadStatus = true;
        }
      }

      if (originalMessageId == null || targetP != myPubkey || !isReadStatus) return true;

      final chatKey = ChatManager.instance.getChatKey(myPubkey, senderPubkey);
      final message = await ChatManager.instance.getMessageById(originalMessageId, chatKey);

      // Message not found — could be out-of-order delivery, but returning
      // false here causes repeated retries from other relays with no effect.
      // Return true so the event is marked processed.
      if (message == null) return true;

      if (message.senderPubkey != myPubkey) return true;

      await ChatManager.instance.updateMessageStatus(
        originalMessageId,
        'read',
        chatKey: chatKey,
      );

      onMessageReceived?.call();
      return true;
    } catch (e) {
      DebugLogger.log('[Receipt] Handle error | $e', type: 'ERROR');
      return false;
    }
  }

  Future<void> _confirmReaction(String giftWrapId) async {
    final info = _reactionAcks.remove(giftWrapId);
    if (info == null) return;
    _reactionAcks.removeWhere((_, v) => v[1] == info[1] && v[2] == info[2]);
    _reactionTimestamps.remove(info[3]);
    // info layout: [chatKey, messageId, reactorPubkey, tsKey]
    await ChatManager.instance.removePendingReaction(
      chatKey: info[0],
      messageId: info[1],
      reactorPubkey: info[2],
    );
    onMessageReceived?.call();
  }

  void _scheduleReactionRetry() {
    if (_reactionRetryTimer != null || _reactionRetryCount >= 6) return;
    _reactionRetryCount++;
    _reactionRetryTimer = Timer(const Duration(seconds: 20), () {
      _reactionRetryTimer = null;
      _processPendingReactions();
    });
  }

  void _handleOk(List<dynamic> decoded, String url) {
    try {
      if (decoded.length < 3) return;
      final eventId = decoded[1].toString();
      final accepted = decoded[2] == true;
      final msg = decoded.length >= 4 ? decoded[3].toString() : '';

      // NIP-42: AUTH response must get an OK.
      if (_pendingAuthEventIds.containsKey(eventId)) {
        final relayUrl = _pendingAuthEventIds.remove(eventId)!;
        if (accepted) {
          _authenticatedRelays.add(relayUrl);
          DebugLogger.log('[AUTH] Confirmed on $relayUrl');
          final myPubkey = AppSettings.instance.myPubkey;
          if (myPubkey.isNotEmpty) {
            _sendSubscriptions(relayUrl, myPubkey, _computeLatestContactTime());
          }
        } else {
          DebugLogger.log('[AUTH] Rejected on $relayUrl | $msg', type: 'ERROR');
        }
        return;
      }

      if (eventId == _dmRelayListEventId) {
        if (accepted) {
          _dmRelayListAcks.add(url);
          if (_dmRelayListAcks.length >= 2) _markDmRelayListPublished();
        } else {
          DebugLogger.log('[DM relays] Rejected by $url | $msg');
        }
        return;
      }

      if (accepted && _reactionAcks.containsKey(eventId)) {
        _confirmReaction(eventId);
        return;
      }

      if (accepted) {
        ChatManager.instance.updateMessageStatusByGiftWrap(eventId, 'sent').then((_) => _processPendingReactions());
        onMessageReceived?.call();
        if (onMessageDelivered != null) onMessageDelivered!(eventId);
      }
    } catch (e) {
      DebugLogger.log('[Relay] OK handler error | $e', type: 'ERROR');
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String receiverPubkey,
    required String plaintext,
    String? replyToId,
    String? replyToContent,
    int? messageTimestampMs,
    FileMessage? file,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) {
        DebugLogger.log('[Message] Missing keys in sendMessage', type: 'ERROR');
        throw Exception('Missing pubkey or privkey');
      }

      final wrappedList = await _wrapOutgoing(
        plaintext: plaintext,
        receiverPubkey: receiverPubkey,
        replyToId: replyToId,
        timestampMs: messageTimestampMs,
        file: file,
      );
      final wrappedRecipient = wrappedList[0];
      final wrappedSelf = wrappedList[1];

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", wrappedRecipient.giftWrap]));
          entry.value.sink.add(jsonEncode(["EVENT", wrappedSelf.giftWrap]));
        }
      }

      final contactsBox = Hive.box<Contact>('contacts');
      final myContact = contactsBox.get(myPubkey);
      final senderName = (myContact != null && myContact.isSaved)
          ? myContact.displayName
          : AppSettings.formatDisplayName(myPubkey);

      _triggerCloudflareNotification(
        receiverPubkey: receiverPubkey,
        senderPubkey: myPubkey,
        eventId: wrappedRecipient.giftWrapId,
        senderName: senderName,
        ciphertext: wrappedRecipient.giftWrap['content']?.toString() ?? '',
        ephemeralPubkey: wrappedRecipient.giftWrap['pubkey']?.toString() ?? '',
      );

      return {
        'giftWrap': wrappedRecipient.giftWrap,
        'giftWrapId': wrappedRecipient.giftWrapId,
        'rumorId': wrappedRecipient.rumorId,
        'rumorTimestamp': wrappedRecipient.rumorTimestamp,
      };
    } catch (e) {
      DebugLogger.log('[NIP-17] sendMessage failed | $e', type: 'ERROR');
      throw Exception('NIP-17 sendMessage failed: $e');
    }
  }

  /// One rumor wrapped for the receiver and for ourselves. A file message is a
  /// kind 15 rumor whose content is the file address.
  Future<List<Nip17Wrapped>> _wrapOutgoing({
    required String plaintext,
    required String receiverPubkey,
    String? replyToId,
    int? timestampMs,
    FileMessage? file,
  }) {
    final myPubkey = AppSettings.instance.myPubkey;
    return Nip17.wrapMulti(
      plaintext: file?.url ?? plaintext,
      senderPrivkey: AppSettings.instance.myPrivkey,
      senderPubkey: myPubkey,
      receiverPubkeys: [receiverPubkey, myPubkey],
      rumorReceiverPubkey: receiverPubkey,
      replyToId: file == null ? replyToId : null,
      forcedTimestampSec: timestampMs != null ? timestampMs ~/ 1000 : null,
      kind: file == null ? Nip17.kindRumor : Nip17.kindFile,
      customTags: file?.rumorTags(receiver: receiverPubkey, replyToId: replyToId),
    );
  }

  void _triggerCloudflareNotification({
    required String receiverPubkey,
    required String senderPubkey,
    required String eventId,
    required String senderName,
    required String ciphertext,
    required String ephemeralPubkey,
    String type = 'chat',
  }) async {
    const workerUrl = 'https://chatme-notifier.cintanyanessa.workers.dev/';
    const secretKey = 'chatme2026secret';

    try {
      final response = await http.post(
        Uri.parse(workerUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Secret-Key': secretKey,
        },
        body: jsonEncode({
          'receiverPubkey': receiverPubkey,
          'senderPubkey': senderPubkey,
          'eventId': eventId,
          'senderName': senderName,
          'ciphertext': ciphertext,
          'ephemeralPubkey': ephemeralPubkey,
          'type': type,
        }),
      ).timeout(const Duration(seconds: 10));

      DebugLogger.log('[Cloudflare] Status ${response.statusCode}${response.statusCode != 200 ? ' | body: ${response.body}' : ''}');
    } catch (e) {
      DebugLogger.log('[Cloudflare] Error | $e', type: 'WARN');
    }
  }

  // Persistent cache using Hive
  Box<String>? _profilePictureBox;

  Box<String> get _profilePics {
    _profilePictureBox ??= Hive.box<String>('profile_pictures');
    return _profilePictureBox!;
  }

  /// Persistent dedup store: eventId -> timestamp (ms) when processed.
  /// Skips already-processed events before NIP-17 unwrap on cold start.
  /// Entries older than 3 days are pruned by [_startCleanupTimer].
  Box? _processedEventsBox;
  Box get _processedEvents {
    _processedEventsBox ??= Hive.box('processed_events');
    return _processedEventsBox!;
  }

  /// Synchronously gets a cached profile picture URL for [pubkey].
  String? getProfilePictureSync(String pubkey) {
    try {
      if (_profilePics.containsKey(pubkey)) {
        final cached = _profilePics.get(pubkey);
        if (cached != null && cached.isNotEmpty) return cached;
      }
    } catch (_) {}
    return null;
  }

  /// Pre-caches all profile pictures stored in Hive into RAM memory.
  void precacheAllProfilePictures() {
    try {
      final box = _profilePics;
      for (final key in box.keys) {
        final url = box.get(key);
        if (url != null && url.isNotEmpty) {
          UserAvatar.precacheProvider(key.toString(), url);
        }
      }
    } catch (_) {}
  }

  final Map<String, List<Completer<String?>>> _profileWaiters = {};

  Future<String?> fetchProfilePicture(String pubkey) async {
    if (_profilePics.containsKey(pubkey)) {
      final cached = _profilePics.get(pubkey);
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final isAlreadyInFlight = _profileWaiters.containsKey(pubkey);
    final completer = Completer<String?>();
    _profileWaiters.putIfAbsent(pubkey, () => []).add(completer);

    if (isAlreadyInFlight) {
      return completer.future;
    }

    final tempSubId = 'profile_${pubkey.substring(0, 12)}';
    bool sentToAtLeastOne = false;
    for (final entry in _connections.entries) {
      if (_connectionStatus[entry.key] == true) {
        try {
          final req = jsonEncode(["REQ", tempSubId, {
            "kinds": [0],
            "authors": [pubkey],
            "limit": 1,
          }]);
          entry.value.sink.add(req);
          sentToAtLeastOne = true;
        } catch (_) {}
      }
    }

    if (!sentToAtLeastOne) {
      _profileWaiters.remove(pubkey);
      return null;
    }

    Timer(const Duration(seconds: 4), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  void _resolveProfileWaiters(String pubkey, String? photoUrl) {
    final waiters = _profileWaiters.remove(pubkey);
    if (waiters == null) return;
    for (final c in waiters) {
      if (!c.isCompleted) c.complete(photoUrl);
    }
  }

  void refreshProfileSubscription() {
    if (_subscriptionId == null) return;
    if (!_isInitialized) return;

    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final authorList = <String>[
        ...contactsBox.keys.map((k) => k.toString()),
        AppSettings.instance.myPubkey,
      ];

      final subProfiles = jsonEncode(["REQ", "${_subscriptionId!}_profiles", {
        "kinds": [0],
        "authors": authorList,
      }]);

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          try {
            entry.value.sink.add(subProfiles);
          } catch (_) {}
        }
      }
      DebugLogger.log('[Profile] Subscription refreshed (${authorList.length} authors)');
    } catch (e) {
      DebugLogger.log('[Profile] refreshProfileSubscription failed | $e', type: 'ERROR');
    }
  }

  String _generateNip98Token(String url, String method) {
    final myPubkey = AppSettings.instance.myPubkey;
    final myPrivkey = AppSettings.instance.myPrivkey;
    if (myPubkey.isEmpty || myPrivkey.isEmpty) {
      DebugLogger.log('[NIP98] Cannot generate token: missing keys', type: 'ERROR');
      return '';
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final unsignedEvent = {
      'kind': 27235,
      'pubkey': myPubkey,
      'created_at': now,
      'tags': [
        ['u', url],
        ['method', method],
      ],
      'content': '',
    };

    final eventId = NostrHelpers.generateEventId(unsignedEvent);
    final signature = NostrSigner.sign(eventId, myPrivkey);
    final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};
    final token = base64Url.encode(utf8.encode(jsonEncode(signedEvent)));

    return 'Nostr $token';
  }

  Future<String?> uploadPhotoToNostrBuild(String filePath) async {
    if (kIsWeb) {
      DebugLogger.log('[Upload] Photo upload not supported on web', type: 'WARN');
      return null;
    }

    try {
      final uploadUrl = Uri.parse('https://nostr.build/api/v2/upload/files');
      final token = _generateNip98Token(uploadUrl.toString(), 'POST');
      if (token.isEmpty) {
        DebugLogger.log('[Upload] NIP-98 token empty, upload aborted', type: 'ERROR');
        return null;
      }

      final request = http.MultipartRequest('POST', uploadUrl);
      request.headers['Authorization'] = token;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final response = await request.send().timeout(const Duration(seconds: 30));
      final body = jsonDecode(await response.stream.bytesToString());

      if (response.statusCode == 200) {
        final url = body['data']?[0]?['url'] as String?;
        return url;
      }
      DebugLogger.log('[Upload] Failed: $body', type: 'ERROR');
      return null;
    } catch (e) {
      DebugLogger.log('[Upload] Error | $e', type: 'ERROR');
      return null;
    }
  }

  Future<void> broadcastProfileKind0({String? photoUrl, bool removePhoto = false}) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;
      // Only publish a real global ID handle as the name. While the user's
      // global ID is disconnected we omit `name` entirely rather than
      // publishing an npub stub, so peers never store a placeholder as our
      // identity.
      final String? myName = AppSettings.instance.myNip05.isNotEmpty
          ? AppSettings.instance.myNip05.split('@')[0]
          : null;

      String? effectivePhotoUrl = photoUrl;
      if (removePhoto) {
        effectivePhotoUrl = null;
      } else if (photoUrl == null) {
        effectivePhotoUrl = AppSettings.instance.myPhotoUrl.isNotEmpty
            ? AppSettings.instance.myPhotoUrl
            : null;
      }

      final content = jsonEncode({
        if (myName != null && myName.isNotEmpty) 'name': myName,
        if (AppSettings.instance.myNip05.isNotEmpty)
          'nip05': AppSettings.instance.myNip05,
        if (effectivePhotoUrl != null && effectivePhotoUrl.isNotEmpty) 'picture': effectivePhotoUrl,
      });

      final unsignedEvent = {
        'pubkey': myPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 0,
        'tags': [],
        'content': content,
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);
      final signature = NostrSigner.sign(eventId, myPrivkey);
      final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", signedEvent]));
        }
      }

      if (effectivePhotoUrl != null && effectivePhotoUrl.isNotEmpty) {
        _profilePics.put(myPubkey, effectivePhotoUrl);
      } else {
        _profilePics.delete(myPubkey);
      }
      UserAvatar.invalidate(myPubkey);
      onMessageReceived?.call();
    } catch (e) {
      DebugLogger.log('[Profile] Broadcast kind 0 failed | $e', type: 'ERROR');
    }
  }

  bool _isDmRelayListPublished(String myPubkey) {
    try {
      final done = Hive.box('settings').get('dm_relay_list_$myPubkey');
      if (done is! Map) return false;
      final at = done['at'] is int ? done['at'] as int : 0;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return done['list'] == dmInboxRelays.join(',') &&
          nowSec - at < 7 * 86400;
    } catch (e) {
      return false;
    }
  }

  void _markDmRelayListPublished() {
    _dmRelayListRetryTimer?.cancel();
    _dmRelayListRetryTimer = null;
    _dmRelayListEventId = null;
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      Hive.box('settings').put('dm_relay_list_$myPubkey', {
        'list': dmInboxRelays.join(','),
        'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      DebugLogger.log('[DM relays] kind 10050 accepted by ${_dmRelayListAcks.length} relays');
    } catch (e) {
      DebugLogger.log('[DM relays] Saving state failed | $e', type: 'ERROR');
    }
  }

  /// Publishes our NIP-17 DM relay list (kind 10050). It is replaceable, so
  /// it is sent once per week or whenever [dmInboxRelays] changes, and counts
  /// as done after at least two relays acknowledge it.
  Future<void> publishDmRelayList() async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;
      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;
      if (_isDmRelayListPublished(myPubkey)) return;
      if (_dmRelayListAttempts >= 6) return;

      final last = _lastDmRelayListAttempt;
      if (last != null && DateTime.now().difference(last).inSeconds < 15) return;
      _lastDmRelayListAttempt = DateTime.now();
      _dmRelayListAttempts++;

      final Map<String, dynamic> unsignedEvent = {
        'pubkey': myPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': Nip17.kindDmRelayList,
        'tags': Nip17.dmRelayListTags(dmInboxRelays),
        'content': '',
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);
      final signature = NostrSigner.sign(eventId, myPrivkey);
      final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};

      _dmRelayListEventId = eventId;
      _dmRelayListAcks.clear();

      int sent = 0;
      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", signedEvent]));
          sent++;
        }
      }
      DebugLogger.log('[DM relays] kind 10050 sent to $sent relays (attempt $_dmRelayListAttempts)');

      _dmRelayListRetryTimer?.cancel();
      _dmRelayListRetryTimer = Timer(const Duration(seconds: 20), publishDmRelayList);
    } catch (e) {
      DebugLogger.log('[DM relays] Publish kind 10050 failed | $e', type: 'ERROR');
    }
  }

  Future<void> sendReceipt(String originalRumorId, String receiverPubkey, String status) async {
    if (!AppSettings.instance.readReceiptsEnabled) return;
    try {
      final myPrivkey = AppSettings.instance.myPrivkey;
      final myPubkey = AppSettings.instance.myPubkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;

      final wrapped = await Nip17.wrap(
        plaintext: status,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkey: receiverPubkey,
        kind: Nip17.kindReadReceipt,
        customTags: [
          ['e', originalRumorId],
          ['p', receiverPubkey],
        ],
      );

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", wrapped.giftWrap]));
        }
      }
    } catch (e) {
      DebugLogger.log('[Receipt] Send failed | $e', type: 'ERROR');
    }
  }

  Future<bool> sendReaction({
    required String messageId,
    required String receiverPubkey,
    required String emoji,
    String? targetAuthorPubkey,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return false;

      final tsKey = '$messageId|$emoji';
      final stableTs = _reactionTimestamps.putIfAbsent(
        tsKey,
            () => DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final author = (targetAuthorPubkey == null || targetAuthorPubkey.isEmpty)
          ? receiverPubkey
          : targetAuthorPubkey;
      final reactionTags = <List<String>>[
        ['e', messageId],
        ['p', author],
        if (author != receiverPubkey) ['p', receiverPubkey],
        ['k', '14'],
      ];

      final wrappedList = await Nip17.wrapMulti(
        plaintext: emoji,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkeys: [receiverPubkey, myPubkey],
        rumorReceiverPubkey: receiverPubkey,
        kind: Nip17.kindReaction,
        customTags: reactionTags,
        forcedTimestampSec: stableTs,
      );
      final wrappedRecipient = wrappedList[0];
      final wrappedSelf = wrappedList[1];

      _reactionAcks[wrappedRecipient.giftWrapId] = [
        ChatManager.instance.getChatKey(myPubkey, receiverPubkey),
        messageId,
        myPubkey,
        tsKey,
      ];

      bool sentToAtLeastOne = false;
      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          try {
            entry.value.sink.add(jsonEncode(["EVENT", wrappedRecipient.giftWrap]));
            entry.value.sink.add(jsonEncode(["EVENT", wrappedSelf.giftWrap]));
            sentToAtLeastOne = true;
          } catch (e) {
            DebugLogger.log('[Relay] Send reaction to ${entry.key} failed | $e', type: 'ERROR');
          }
        }
      }
      return sentToAtLeastOne;
    } catch (e) {
      DebugLogger.log('[NIP-17] Reaction send failed | $e', type: 'ERROR');
      return false;
    }
  }

  Future<void> sendCallSignal(String recipientPubkey, Map<String, dynamic> signalData) {
    // Capture the signaling context now: the state changes while the signal
    // waits in the queue and is wrapped on the background isolate.
    final bool callerNotConnected =
        CallManager.instance.currentCallDirection == CallType.outgoing &&
            CallManager.instance.callState != CallState.active &&
            !CallManager.instance.wasCallConnected;

    // Chain sends so signaling order is preserved even though wrapping runs
    // asynchronously on a background isolate. A failure must not break the
    // chain for the next signal.
    final next = _callSignalSendChain.then(
      (_) => _sendCallSignalNow(
        recipientPubkey,
        signalData,
        callerNotConnected: callerNotConnected,
      ),
    );
    _callSignalSendChain = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<void> _sendCallSignalNow(
    String recipientPubkey,
    Map<String, dynamic> signalData, {
    required bool callerNotConnected,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;

      final wrapped = await Nip17Isolate.wrap(
        plaintext: jsonEncode(signalData),
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkey: recipientPubkey,
        kind: Nip17.kindCallSignal,
        customTags: [
          ['p', recipientPubkey],
        ],
      );

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", wrapped.giftWrap]));
        }
      }

      // Wake up the receiver's device when it is closed or in background.
      // Only the offer rings a phone; other signals stay relay-only.
      if (signalData['type'] == 'offer') {
        final contactsBox = Hive.box<Contact>('contacts');
        final myContact = contactsBox.get(myPubkey);
        final callerName = (myContact != null && myContact.isSaved)
            ? myContact.displayName
            : AppSettings.formatDisplayName(myPubkey);

        _triggerCloudflareNotification(
          receiverPubkey: recipientPubkey,
          senderPubkey: myPubkey,
          eventId: 'call_${DateTime.now().millisecondsSinceEpoch}',
          senderName: callerName,
          ciphertext: '',
          ephemeralPubkey: '',
          type: 'call',
        );
      }

      // The caller gave up before the call was answered (cancel or timeout):
      // also dismiss the ringing notification on the receiver's device.
      // Only the caller's side sends this; a receiver declining is skipped.
      if (signalData['type'] == 'hangup' && callerNotConnected) {
        _triggerCloudflareNotification(
          receiverPubkey: recipientPubkey,
          senderPubkey: myPubkey,
          eventId: 'cancel_${DateTime.now().millisecondsSinceEpoch}',
          senderName: 'ChatMe',
          ciphertext: '',
          ephemeralPubkey: '',
          type: 'call_cancel',
        );
      }

    } catch (e) {
      DebugLogger.log('[Call] Send signal failed | $e', type: 'ERROR');
    }
  }

  /// Buffers a contact-row update during a drain; written once per batch
  /// by [_flushContactBuffer]. The merge logic matches the old per-message
  /// write, except that the unread badge is also muted while the initial
  /// sync gate is active (a restore / first login pulls history, not fresh
  /// conversation).
  void _bufferContactUpdate(
    String peerPubkey,
    String message,
    int timestamp,
    bool isFromMe,
    bool alreadyExists,
  ) {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      var contact = _contactBuffer[peerPubkey] ?? contactsBox.get(peerPubkey);

      if (contact == null) {
        final bool muteUnread = isFromMe ||
            currentlyChattingWith == peerPubkey ||
            alreadyExists ||
            SyncGate.isActive;
        contact = Contact(
          pubkey: peerPubkey,
          name: '',
          lastChatTime: timestamp,
          lastMessage: message,
          unreadCount: muteUnread ? 0 : 1,
          isSaved: false,
        );
        // Firebase name fetch: once per new peer per drain, not per message.
        _bufferedNewContacts.add(peerPubkey);
      } else {
        if (timestamp >= contact.lastChatTime) {
          contact.lastChatTime = timestamp;
          contact.lastMessage = message.length > 50 ? '${message.substring(0, 50)}...' : message;
        }

        if (!isFromMe &&
            currentlyChattingWith != peerPubkey &&
            !alreadyExists &&
            !SyncGate.isActive) {
          contact.unreadCount++;
        }
        if (currentlyChattingWith == peerPubkey) contact.unreadCount = 0;
      }
      _contactBuffer[peerPubkey] = contact;
    } catch (e) {
      DebugLogger.log('[Contact] Buffer update failed | $e', type: 'ERROR');
    }
  }

  /// Writes the buffered contact rows and fires the one-time hooks for
  /// peers seen for the first time in this batch.
  Future<void> _flushContactBuffer() async {
    if (_contactBuffer.isEmpty && _bufferedNewContacts.isEmpty) return;
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      for (final entry in _contactBuffer.entries) {
        await contactsBox.put(entry.key, entry.value);
      }
      _contactBuffer.clear();

      if (_bufferedNewContacts.isNotEmpty) {
        for (final peerPubkey in _bufferedNewContacts) {
          AppSettings.hydrateSingleContact(peerPubkey);
        }
        refreshProfileSubscription();
        _bufferedNewContacts.clear();
      }
    } catch (e) {
      DebugLogger.log('[Contact] Flush failed | $e', type: 'ERROR');
    }
  }

  String? _reactionEmojiFrom(String content) {
    final value = content.trim();
    if (value.isEmpty || value == '+') return '👍';
    if (value == '-') return '👎';
    if (value.length > 32) return null;
    return value;
  }

  Future<bool> _updateMessageReaction(
      String messageId,
      String reactorPubkey,
      String emoji,
      String chatKey
      ) async {
    final bool applied = await ChatManager.instance.mergeReaction(
      chatKey: chatKey,
      messageId: messageId,
      reactorPubkey: reactorPubkey,
      emoji: emoji,
    );
    if (applied) {
      onMessageReceived?.call();
      return true;
    }
    return false;
  }

  String _extractReceiverPubkey(dynamic tags) {
    if (tags is List) {
      for (var t in tags) {
        if (t is List && t.length > 1 && t[0] == 'p') return t[1].toString();
      }
    }
    return '';
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (t) {
      // Trim in-memory dedup Set.
      if (_processedEventIds.length > 5000) {
        final list = _processedEventIds.toList();
        _processedEventIds.clear();
        _processedEventIds.addAll(list.sublist(list.length - 1000));
      }

      // Prune persistent dedup entries older than the sync window (3 days).
      try {
        final box = _processedEvents;
        final cutoff = DateTime.now().millisecondsSinceEpoch -
            (3 * 24 * 3600 * 1000);
        final toDelete = <dynamic>[];
        for (final key in box.keys) {
          final ts = box.get(key);
          if (ts is int && ts < cutoff) {
            toDelete.add(key);
          }
        }
        for (final k in toDelete) {
          box.delete(k);
        }
        if (toDelete.isNotEmpty) {
          DebugLogger.log('[Cleanup] Pruned ${toDelete.length} old processed_events');
        }
      } catch (_) {}
    });
  }

  void _handleError(String url, dynamic e) {
    _connectionStatus[url] = false;
    _updateConnectionStatus();
    // A dropped relay will never send its EOSE; forget it (a reconnect
    // re-adds it via _sendSubscriptions while the gate is still open).
    _onIncomingSyncDone(url, 'connection error');
    _scheduleReconnect(url);
  }

  void _handleDisconnect(String url) {
    _connectionStatus[url] = false;
    _updateConnectionStatus();
    _onIncomingSyncDone(url, 'disconnected');
    _scheduleReconnect(url);
  }

  void _scheduleReconnect(String url) {
    if (_reconnectScheduled.contains(url)) return;

    final attempts = _reconnectAttempts[url] ?? 0;
    if (attempts > 10) return;

    _reconnectScheduled.add(url);

    final delay = Duration(seconds: min(5 * (1 << attempts), 60));
    Future.delayed(delay, () {
      _reconnectScheduled.remove(url);

      if (_connections.containsKey(url) && _connectionStatus[url] == false) {
        _reconnectAttempts[url] = attempts + 1;
        _connectToRelay(url, AppSettings.instance.myPubkey, _computeLatestContactTime());
      }
    });
  }

  void _updateConnectionStatus() {
    final count = _connectionStatus.values.where((s) => s == true).length;
    final bool wasConnected = _isConnected.value;
    final bool isNowConnected = count > 0;

    _isConnected.value = isNowConnected;
    _connectedCount.value = count;

    if (!wasConnected && isNowConnected) {
      _processOfflineQueue();
      refreshProfileSubscription();
      Future.delayed(const Duration(seconds: 5), publishDmRelayList);
    }
  }

  Future<ListEdit> addRelay(RelayGroup group, String input) async {
    final settings = AppSettings.instance;
    final isInbox = group == RelayGroup.inbox;
    final edit = ServerLists.add(
      isInbox ? settings.inboxRelays : settings.otherRelays,
      input,
      normalize: ServerAddress.relay,
      max: isInbox ? ListLimits.inboxMax : ListLimits.otherMax,
      taken: isInbox ? settings.otherRelays : settings.inboxRelays,
    );
    if (!edit.ok) return edit;

    await _applyRelayLists(
      inbox: isInbox ? edit.list : settings.inboxRelays,
      other: isInbox ? settings.otherRelays : edit.list,
    );
    return edit;
  }

  Future<ListEdit> removeRelay(RelayGroup group, String url) async {
    final settings = AppSettings.instance;
    final isInbox = group == RelayGroup.inbox;
    final edit = ServerLists.remove(
      isInbox ? settings.inboxRelays : settings.otherRelays,
      url,
      minimum: isInbox ? ListLimits.inboxMin : 0,
    );
    if (!edit.ok) return edit;

    await _applyRelayLists(
      inbox: isInbox ? edit.list : settings.inboxRelays,
      other: isInbox ? settings.otherRelays : edit.list,
    );
    return edit;
  }

  Future<void> resetRelaysToDefaults() {
    final defaults = RelayLists.defaults();
    return _applyRelayLists(inbox: defaults.inbox, other: defaults.other);
  }

  /// Saves the lists, opens the new connections, closes the removed ones and
  /// announces the inbox list again when it changed.
  Future<void> _applyRelayLists({
    required List<String> inbox,
    required List<String> other,
  }) async {
    final settings = AppSettings.instance;
    final beforeInbox = List.of(settings.inboxRelays);
    final diff = RelayDiff.between(
      settings.allRelays,
      [...inbox, ...other],
    );

    await settings.setRelayLists(inbox: inbox, other: other);

    for (final url in diff.removed) {
      _closeConnection(url);
      _reconnectAttempts.remove(url);
      _reconnectScheduled.remove(url);
    }
    if (_isInitialized && diff.added.isNotEmpty) {
      final myPubkey = settings.myPubkey;
      final latestTime = _computeLatestContactTime();
      for (final url in diff.added) {
        _reconnectAttempts.remove(url);
        _connectToRelay(url, myPubkey, latestTime);
      }
    }
    _updateConnectionStatus();

    if (!listEquals(beforeInbox, inbox)) {
      _dmRelayListAttempts = 0;
      _lastDmRelayListAttempt = null;
      publishDmRelayList();
    }
    relayListVersion.value++;
  }

  void connectIfNeeded() {
    if (_connections.isEmpty || !_isConnected.value) connect();
  }

  ValueListenable<bool> get isConnected => _isConnected;
  ValueListenable<int> get connectedCount => _connectedCount;

  Future<void> dispose() async {
    disconnect();
  }

  Future<void> _processOfflineQueue() async {
    if (_isProcessingQueue) return;

    _isProcessingQueue = true;
    try {
      _reactionRetryCount = 0;
      await _processPendingReactions();

      final pendingMessages = await ChatManager.instance.getPendingMessages();
      if (pendingMessages.isEmpty) return;

      DebugLogger.log('[Queue] Processing ${pendingMessages.length} pending message(s)');

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      for (var snapshot in pendingMessages) {
        final msg = await ChatManager.instance.getMessageById(snapshot.id, snapshot.chatKey);
        if (msg == null) continue;
        if (msg.status == 'sent' || msg.status == 'read') continue;

        final lastAttempt = _lastQueueAttempt[msg.id] ?? 0;
        if (nowMs - lastAttempt < 60000) continue;
        _lastQueueAttempt[msg.id] = nowMs;

        final plaintext = msg.plaintext.isNotEmpty ? msg.plaintext : msg.content;
        if (plaintext.isEmpty) continue;

        try {
          FileMessage? file = msg.fileMessage;
          if (msg.needsUpload) {
            if (msg.localPath.isEmpty) continue;
            file = await FileSendService.encryptAndUpload(
              source: File(msg.localPath),
              mimeType: msg.file['type'] ?? FileSendService.voiceMimeType,
              durationSeconds: msg.fileDurationSeconds,
              width: msg.imageSize?.width,
              height: msg.imageSize?.height,
              servers: AppSettings.instance.blossomServers,
            );
            await ChatManager.instance.setFile(msg.id, msg.chatKey, file.toMap());
          }

          final wrappedList = await _wrapOutgoing(
            plaintext: plaintext,
            receiverPubkey: msg.receiverPubkey,
            replyToId: msg.replyToId,
            timestampMs: msg.timestamp,
            file: file,
          );
          final wrappedRecipient = wrappedList[0];
          final wrappedSelf = wrappedList[1];

          bool sentToAtLeastOne = false;
          for (final entry in _connections.entries) {
            if (_connectionStatus[entry.key] == true) {
              try {
                entry.value.sink.add(jsonEncode(["EVENT", wrappedRecipient.giftWrap]));
                entry.value.sink.add(jsonEncode(["EVENT", wrappedSelf.giftWrap]));
                sentToAtLeastOne = true;
              } catch (e) {
                DebugLogger.log('[Queue] Send to ${entry.key} failed | $e', type: 'ERROR');
              }
            }
          }

          if (sentToAtLeastOne) {
            await ChatManager.instance.updateMessageIdAndStatus(
              msg.id,
              wrappedRecipient.rumorId,
              'sending',
              msg.chatKey,
              newContent: wrappedRecipient.giftWrap['content']?.toString() ?? '',
              newGiftWrapId: wrappedRecipient.giftWrapId,
            );
            DebugLogger.log('[Queue] Sent, awaiting OK: ${wrappedRecipient.giftWrapId}');
          } else {
            DebugLogger.log('[Queue] No relay connected, deferring ${msg.id}', type: 'WARN');
          }
        } catch (e) {
          DebugLogger.log('[Queue] Failed to wrap pending msg ${msg.id} | $e', type: 'ERROR');
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }

      await _processPendingReactions();

    } catch (e) {
      DebugLogger.log('[Queue] Process failed | $e', type: 'ERROR');
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _processPendingReactions() async {
    if (_isProcessingReactions) return;
    _isProcessingReactions = true;

    bool anyUnacked = false;
    try {
      final myKey = AppSettings.instance.myPubkey;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final targets = <List<String>>[];
      for (final m in ChatManager.instance.allMessagesSync()) {
        final bool confirmed = (m.status == 'sent' || m.status == 'read') &&
            !m.id.startsWith('temp_') &&
            !m.id.startsWith('pending_');
        if (!confirmed || m.pendingReactions.isEmpty) continue;
        final peerKey = m.senderPubkey == myKey ? m.receiverPubkey : m.senderPubkey;
        for (final e in m.pendingReactions.entries) {
          targets.add([m.id, m.senderPubkey, peerKey, e.value]);
        }
      }

      for (final t in targets) {
        anyUnacked = true;
        final attemptKey = '${t[0]}|${t[3]}';
        final last = _lastReactionAttempt[attemptKey] ?? 0;
        if (nowMs - last < 15000) continue;
        _lastReactionAttempt[attemptKey] = nowMs;

        try {
          final sent = await sendReaction(
            messageId: t[0],
            targetAuthorPubkey: t[1],
            receiverPubkey: t[2],
            emoji: t[3],
          );
          if (!sent) break;
          DebugLogger.log('[Queue] Reaction ${t[3]} sent for ${t[0]}, awaiting OK');
        } catch (e) {
          DebugLogger.log('[Queue] Failed to send pending reaction for ${t[0]} | $e', type: 'ERROR');
          break;
        }

        await Future.delayed(const Duration(milliseconds: 150));
      }
    } catch (e) {
      DebugLogger.log('[Queue] Process pending reactions failed | $e', type: 'ERROR');
    } finally {
      _isProcessingReactions = false;
    }

    if (anyUnacked) _scheduleReactionRetry();
  }
}