// relay_manager.dart

import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'call_manager.dart';
import 'notification_handler.dart';
import 'call.dart';
import 'main.dart';
import 'chat_manager.dart';
import 'core/crypto/nip04.dart';
import 'core/crypto/nip17.dart';
import 'core/crypto/nostr_protocol.dart';
import 'services/app_settings.dart';
import 'models/contact.dart';
import 'core/utils/debug_logger.dart';
import 'models/chat_message.dart';
import 'services/nostr_service.dart';
import 'package:http/http.dart' as http;

class RelayManager {
  Function? onMessageReceived;
  String? currentlyChattingWith;

  Function(Map<String, dynamic>)? onSignalReceived;

  /// Recommended free relays optimised for NIP-17 gift-wrap (kind 1059).
  /// Ordered by relevance for DM delivery.
  final List<String> relays = [
    'wss://messaging.coracle.social', // dedicated messaging / NIP-17
    'wss://nos.lol',
    'wss://relay.damus.io',
    'wss://relay.primal.net',
  ];

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
  final Map<String, int> _lastKind0Timestamp = {};

  /// Timestamp (ms) of the last re-send attempt per message ID.
  /// Prevents the offline queue from hammering the same message every tick.
  final Map<String, int> _lastQueueAttempt = {};

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

      // Compute latestTime once here, not 7× inside each _connectToRelay.
      final int latestTime = _computeLatestContactTime();

      for (var i = 0; i < relays.length; i++) {
        Future.delayed(Duration(milliseconds: i * 300), () {
          _connectToRelay(relays[i], myPubkey, latestTime);
        });
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
      if (message.contains('"EOSE"')) return;

      final decoded = jsonDecode(message);
      if (decoded is! List || decoded.isEmpty) return;

      final type = decoded[0];

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
        if (lower.contains('auth-required') &&
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
                if (name != null && name.isNotEmpty) {
                  try {
                    final contactsBox = Hive.box<Contact>('contacts');
                    final contact = contactsBox.get(pubkey);
                    if (contact != null && !contact.hasGlobalId) {
                      contact.name = name;
                      await contactsBox.put(pubkey, contact);
                    }
                  } catch (_) {}
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

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final myPubkey = AppSettings.instance.myPubkey;
      final senderPubkey = event['pubkey']?.toString() ?? '';

      if (kind == 1 || kind == 4 || kind == 7 || kind == 1059) {
        if (kind == 7) {
          if (senderPubkey == myPubkey) {
            _processedEventIds.add(eventId);
            return;
          }
          if (now - createdAt > 60) {
            _processedEventIds.add(eventId);
            return;
          }
        }

        if (kind == 1 || kind == 4 || kind == 1059) {
          final bool success = await _processIncomingEvent(event);
          if (success) {
            _processedEventIds.add(eventId);
            try {
              _processedEvents.put(eventId, DateTime.now().millisecondsSinceEpoch);
            } catch (_) {}
          }
        }

        if (kind == 7) {
          final bool success = await _handleReceiptEvent(event);
          if (success) {
            _processedEventIds.add(eventId);
            try {
              _processedEvents.put(eventId, DateTime.now().millisecondsSinceEpoch);
            } catch (_) {}
          }
        }
      }
    } finally {
      _inFlightEventIds.remove(eventId);
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
          if (savedContact != null && savedContact.isSaved) {
            finalDisplayName = savedContact.name;
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
        } else {
          cm.pendingIncoming = PendingIncomingCall(
            callerPubkey: callerPubkey,
            callerName: finalDisplayName,
            callerColor: incomingPeerColor,
            remoteSdp: signalData['data'],
          );

          NotificationHandler.showIncomingCall(
            callerPubkey: callerPubkey,
            callerName: finalDisplayName,
          );
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

  Future<bool> _processIncomingEvent(Map<String, dynamic> event) async {
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

      Nip17Result? nip17Result;

      if (event['kind'] == 1059) {
        try {
          nip17Result = await Nip17.unwrap(
            giftWrapEvent: event,
            receiverPrivkey: myPrivkey,
            receiverPubkey: myPubkey,
          );
          decrypted = nip17Result.plaintext;
          actualSenderPubkey = nip17Result.senderPubkey;
          timestamp = nip17Result.timestamp;
          actualEventId = nip17Result.rumorId;
          receiverPubkey = nip17Result.receiverPubkey;

          final bool isFromMe = (actualSenderPubkey == myPubkey);
          peerPubkey = isFromMe ? receiverPubkey : actualSenderPubkey;
        } catch (e) {
          DebugLogger.log('[NIP-17] Unwrap failed | $e', type: 'ERROR');
          return false;
        }
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

      if (decrypted.startsWith('CALL_SIGNAL:')) {
        try {
          final signalJson = decrypted.substring('CALL_SIGNAL:'.length);
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

            if ((type == 'answer' || type == 'candidate') &&
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

      // Reaction
      if (decrypted.startsWith('REACTION:')) {
        final parts = decrypted.split(':');
        if (parts.length >= 3) {
          final emoji = parts[1];
          final targetMessageId = parts[2];
          if (targetMessageId.isNotEmpty) {
            final bool applied = await _updateMessageReaction(targetMessageId, actualSenderPubkey, emoji, chatKey);
            return applied ? true : false;
          }
        }
      }

      // Read receipt
      if (decrypted.startsWith('READ_RECEIPT:')) {
        final parts = decrypted.split(':');
        if (parts.length >= 3) {
          final targetMessageId = parts[1];
          final status = parts[2];
          if (targetMessageId.isNotEmpty) {
            final bool applied = await ChatManager.instance.updateMessageStatus(
              targetMessageId,
              status,
              chatKey: chatKey,
            );
            return applied ? true : false;
          }
        }
      }

      // Legacy kind-7 reaction handling
      if (event['kind'] == 7) {
        String? targetId;
        for (var t in tags) {
          if (t is List && t.length > 1 && t[0] == 'e') {
            targetId = t[1].toString();
            break;
          }
        }
        if (targetId != null) {
          final bool applied = await _updateMessageReaction(targetId, actualSenderPubkey, content, chatKey);
          return applied ? true : false;
        }
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
      );

      final bool newlySaved = await ChatManager.instance.saveMessage(chatMessage);
      await ChatManager.instance.repairReplyContent(actualEventId, decrypted, chatKey);
      await ChatManager.instance.repairPendingReplies(chatKey);

      // If saveMessage only updated an existing entry (i.e. this is a
      // duplicate), do not increment the unread badge.
      final bool alreadyExistsActual = !newlySaved;
      await _updateContactWithMessage(peerPubkey, decrypted, timestamp, isFromMe, alreadyExistsActual);

      if (onMessageReceived != null) onMessageReceived!();
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

      if (message == null) return false;

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

      if (accepted) {
        ChatManager.instance.updateMessageStatusByGiftWrap(eventId, 'sent');
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
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) {
        DebugLogger.log('[Message] Missing keys in sendMessage', type: 'ERROR');
        throw Exception('Missing pubkey or privkey');
      }

      final wrappedList = await Nip17.wrapMulti(
        plaintext: plaintext,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkeys: [receiverPubkey, myPubkey],
        rumorReceiverPubkey: receiverPubkey,
        replyToId: replyToId,
        forcedTimestampSec: messageTimestampMs != null
            ? messageTimestampMs ~/ 1000
            : null,
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

  Future<void> broadcastProfileKind0({String? photoUrl}) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;
      final myName = AppSettings.instance.myNip05.isNotEmpty
          ? AppSettings.instance.myNip05.split('@')[0]
          : AppSettings.formatDisplayName(myPubkey);

      final content = jsonEncode({
        'name': myName,
        if (AppSettings.instance.myNip05.isNotEmpty)
          'nip05': AppSettings.instance.myNip05,
        if (photoUrl != null) 'picture': photoUrl,
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

      if (photoUrl != null && photoUrl.isNotEmpty) {
        _profilePics.put(myPubkey, photoUrl);
      } else {
        _profilePics.delete(myPubkey);
      }
      UserAvatar.invalidate(myPubkey);
      onMessageReceived?.call();
    } catch (e) {
      DebugLogger.log('[Profile] Broadcast kind 0 failed | $e', type: 'ERROR');
    }
  }

  Future<void> sendReceipt(String originalRumorId, String receiverPubkey, String status) async {
    try {
      final myPrivkey = AppSettings.instance.myPrivkey;
      final myPubkey = AppSettings.instance.myPubkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;

      final receiptPlaintext = 'READ_RECEIPT:$originalRumorId:$status';

      final wrapped = await Nip17.wrap(
        plaintext: receiptPlaintext,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkey: receiverPubkey,
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
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return false;

      final reactionPlaintext = 'REACTION:$emoji:$messageId';

      final wrappedList = await Nip17.wrapMulti(
        plaintext: reactionPlaintext,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkeys: [receiverPubkey, myPubkey],
        rumorReceiverPubkey: receiverPubkey,
        replyToId: messageId,
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

  Future<void> sendCallSignal(String recipientPubkey, Map<String, dynamic> signalData) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;

      final plaintext = 'CALL_SIGNAL:${jsonEncode(signalData)}';

      final wrapped = await Nip17.wrap(
        plaintext: plaintext,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkey: recipientPubkey,
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
    } catch (e) {
      DebugLogger.log('[Call] Send signal failed | $e', type: 'ERROR');
    }
  }

  Future<void> _updateContactWithMessage(String peerPubkey, String message, int timestamp, bool isFromMe, bool alreadyExists) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      Contact? contact = contactsBox.get(peerPubkey);
      final bool isNewContact = contact == null;

      if (contact == null) {
        contact = Contact(
            pubkey: peerPubkey,
            name: '',
            lastChatTime: timestamp,
            lastMessage: message,
            unreadCount: (isFromMe || currentlyChattingWith == peerPubkey || alreadyExists) ? 0 : 1,
            isSaved: false
        );
        AppSettings.hydrateSingleContact(peerPubkey);
      } else {
        if (timestamp >= contact.lastChatTime) {
          contact.lastChatTime = timestamp;
          contact.lastMessage = message.length > 50 ? '${message.substring(0, 50)}...' : message;
        }

        if (!isFromMe && currentlyChattingWith != peerPubkey && !alreadyExists) {
          contact.unreadCount++;
        }
        if (currentlyChattingWith == peerPubkey) contact.unreadCount = 0;
      }
      await contactsBox.put(peerPubkey, contact);

      if (isNewContact) {
        refreshProfileSubscription();
      }
    } catch (e) {
      DebugLogger.log('[Contact] Update failed | $e', type: 'ERROR');
    }
  }

  Future<bool> _updateMessageReaction(
      String messageId,
      String reactorPubkey,
      String emoji,
      String chatKey
      ) async {
    try {
      final box = Hive.box('chats');
      final dynamic raw = box.get(chatKey);
      if (raw is! List) return false;

      final messages = raw.cast<ChatMessage>().toList();
      final index = messages.indexWhere((m) => m.id == messageId);

      if (index != -1) {
        final message = messages[index];
        final updatedReactions = Map<String, String>.from(message.reactions);
        updatedReactions[reactorPubkey] = emoji;

        final updatedMessage = message.copyWith(
          reactions: updatedReactions,
        );

        messages[index] = updatedMessage;
        await box.put(chatKey, messages);

        if (onMessageReceived != null) onMessageReceived!();
        return true;
      } else {
        DebugLogger.log('[Reaction] Target message not found: $messageId', type: 'WARN');
        return false;
      }
    } catch (e) {
      DebugLogger.log('[Reaction] Update failed | $e', type: 'ERROR');
      return false;
    }
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
    _scheduleReconnect(url);
  }

  void _handleDisconnect(String url) {
    _connectionStatus[url] = false;
    _updateConnectionStatus();
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
    }
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

        final myPrivkey = AppSettings.instance.myPrivkey;
        final myPubkey = AppSettings.instance.myPubkey;
        final plaintext = msg.plaintext.isNotEmpty ? msg.plaintext : msg.content;
        if (plaintext.isEmpty) continue;

        try {
          final wrappedList = await Nip17.wrapMulti(
            plaintext: plaintext,
            senderPrivkey: myPrivkey,
            senderPubkey: myPubkey,
            receiverPubkeys: [msg.receiverPubkey, myPubkey],
            rumorReceiverPubkey: msg.receiverPubkey,
            replyToId: msg.replyToId,
            forcedTimestampSec: msg.timestamp ~/ 1000,
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

    try {
      final chatsBox = Hive.box('chats');
      for (var key in chatsBox.keys) {
        final dynamic rawData = chatsBox.get(key);
        if (rawData is! List) continue;

        List<ChatMessage> messages = rawData.cast<ChatMessage>().toList();

        for (int i = 0; i < messages.length; i++) {
          final msg = messages[i];
          final bool isConfirmedSent = (msg.status == 'sent' || msg.status == 'read') &&
              !msg.id.startsWith('temp_') &&
              !msg.id.startsWith('pending_');

          if (!isConfirmedSent) continue;
          if (msg.pendingReactions.isEmpty) continue;

          final pendingMap = Map<String, String>.from(msg.pendingReactions);
          bool messageChanged = false;

          for (final entry in pendingMap.entries) {
            final reactorPubkey = entry.key;
            final emoji = entry.value;

            try {
              final success = await sendReaction(
                messageId: msg.id,
                receiverPubkey: msg.receiverPubkey,
                emoji: emoji,
              );
              if (success) {
                messages[i] = messages[i].copyWith(
                  pendingReactions: Map.from(messages[i].pendingReactions)..remove(reactorPubkey),
                );
                messageChanged = true;
                DebugLogger.log('[Queue] Sent pending reaction $emoji for confirmed message ${msg.id}');
              } else {
                DebugLogger.log('[Queue] No connection, keeping pending reaction for ${msg.id}', type: 'WARN');
                break;
              }
            } catch (e) {
              DebugLogger.log('[Queue] Failed to send pending reaction for ${msg.id} | $e', type: 'ERROR');
              break;
            }

            await Future.delayed(const Duration(milliseconds: 150));
          }

          if (messageChanged) {
            await chatsBox.put(key, messages);
          }
        }
      }
    } catch (e) {
      DebugLogger.log('[Queue] Process pending reactions failed | $e', type: 'ERROR');
    } finally {
      _isProcessingReactions = false;
    }
  }
}