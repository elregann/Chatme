// relay_manager.dart

import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'call_manager.dart';
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

  final List<String> relays = [
    'wss://nip17.com',
    'wss://nos.lol',
    'wss://nostr.mom',
    'wss://relay.damus.io',
    'wss://relay.mostr.pub',
    'wss://relay.noswhere.com',
    'wss://relay.primal.net',
  ];

  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, bool> _connectionStatus = {};
  final Map<String, Timer> _pingTimers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Set<String> _reconnectScheduled = {};
  final Set<String> _processedEventIds = {};
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

      for (var i = 0; i < relays.length; i++) {
        Future.delayed(Duration(milliseconds: i * 300), () {
          _connectToRelay(relays[i], myPubkey);
        });
      }
      _isInitialized = true;
      _isConnecting = false;
    } catch (e) {
      _isConnecting = false;
    }
  }

  void disconnect() {
    _cleanupTimer?.cancel();
    _queueTimer?.cancel();
    _isProcessingQueue = false;
    for (var timer in _pingTimers.values) {
      timer.cancel();
    }
    _pingTimers.clear();

    for (var url in _connections.keys.toList()) {
      _closeConnection(url);
    }

    _connections.clear();
    _connectionStatus.clear();
    _reconnectAttempts.clear();
    _reconnectScheduled.clear();
    _isInitialized = false;
    _isConnecting = false;
    _isConnected.value = false;
    _connectedCount.value = 0;
  }

  Future<void> _connectToRelay(String relayUrl, String myPubkey) async {
    try {
      _closeConnection(relayUrl);

      final channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      _connections[relayUrl] = channel;

      channel.ready.then((_) {}, onError: (e) {
        if (_connections[relayUrl] == channel) {
          _handleError(relayUrl, e);
        }
      });

      final nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int syncSince = nowTimestamp - 2592000;

      try {
        final contactsBox = Hive.box<Contact>('contacts');
        if (contactsBox.isNotEmpty) {
          int latestTime = 0;
          for (var contact in contactsBox.values) {
            if (contact.lastChatTime > latestTime) {
              latestTime = contact.lastChatTime;
            }
          }
          if (latestTime > 0) {
            final computed = (latestTime ~/ 1000) - 3600;
            // NIP-59 randomises gift-wrap `created_at` up to 2 days into
            // the past. A narrower window would silently drop freshly
            // queued messages whose random timestamp happens to fall
            // outside it. Always look back at least 3 days.
            final minimum = nowTimestamp - 259200; // 3 days
            syncSince = computed < minimum ? computed : minimum;
            DebugLogger.log('[Sync] Fetching since ${DateTime.fromMillisecondsSinceEpoch(syncSince * 1000)}');
          }
        }
      } catch (e) {
        DebugLogger.log('[Sync] Failed to compute syncSince, using 30 days default', type: 'WARN');
      }

      final List<int> neededKinds = [1, 4, 7, 1059];

      final subToMe = jsonEncode(["REQ", "${_subscriptionId!}_incoming", {
        "kinds": neededKinds,
        "#p": [myPubkey],
        "since": syncSince
      }]);

      final subFromMe = jsonEncode(["REQ", "${_subscriptionId!}_outgoing", {
        "kinds": neededKinds,
        "authors": [myPubkey],
        "since": syncSince
      }]);

      channel.sink.add(subToMe);
      channel.sink.add(subFromMe);

      final profileSince = nowTimestamp - 86400;
      final subProfiles = jsonEncode(["REQ", "${_subscriptionId!}_profiles", {
        "kinds": [0],
        "since": profileSince
      }]);
      channel.sink.add(subProfiles);

      _startPingTimer(relayUrl, channel);

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

  void _closeConnection(String url) {
    try {
      _pingTimers[url]?.cancel();
      _connections[url]?.sink.close();
      _connections.remove(url);
      _connectionStatus.remove(url);
    } catch (e) {
      DebugLogger.log('[Relay] Close connection error | $e', type: 'ERROR');
    }
  }

  Future<void> _handleData(dynamic data, String url) async {
    try {
      final message = data.toString();
      if (message.contains('"EOSE"') || message.contains('"PONG"')) return;

      final decoded = jsonDecode(message);
      if (decoded is List && decoded.length > 2) {
        if (decoded[0] == "EVENT") await _handleEvent(decoded, url);
        if (decoded[0] == "OK") _handleOk(decoded, url);
      }
    } catch (e) {
      DebugLogger.log('[Relay] Data handling error | $e', type: 'ERROR');
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

                if (picture != null && picture.isNotEmpty) {
                  _profilePics.put(pubkey, picture);
                } else {
                  _profilePics.delete(pubkey);
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

                try {
                  onMessageReceived?.call();
                } catch (_) {}
              }
            }
          }
        } catch (e) {
          DebugLogger.log('[Profile] Cache error | $e', type: 'ERROR');
        }
      }
    }

    if (eventId.isEmpty || _processedEventIds.contains(eventId)) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final myPubkey = AppSettings.instance.myPubkey;
    final senderPubkey = event['pubkey']?.toString() ?? '';

    if (kind == 1 || kind == 4 || kind == 7 || kind == 1059) {
      if (kind == 7) {
        if (senderPubkey == myPubkey) return;
        if (now - createdAt > 60) return;
      }

      _processedEventIds.add(eventId);

      if (kind == 1 || kind == 4 || kind == 1059) {
        _processIncomingEvent(event);
      }

      if (kind == 7) _handleReceiptEvent(event);
    }
  }

  void _processCallSignal(Map<String, dynamic> event) {
    try {
      final rawContent = event['content'] as String?;
      if (rawContent == null || !rawContent.trim().startsWith('{')) return;
      final signalData = jsonDecode(rawContent);
      final callerPubkey = event['pubkey'];

      if (signalData['type'] == 'offer') {
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

        if (navigatorKey.currentContext != null) {
          Navigator.push(
            navigatorKey.currentContext!,
            MaterialPageRoute(
              builder: (context) => CallScreen(
                peerName: finalDisplayName,
                peerPubkey: callerPubkey,
                isIncoming: true,
                relay: this,
                peerColor: incomingPeerColor,
                remoteSdp: signalData['data'],
                onClose: () {},
              ),
            ),
          );
        }
      } else if (signalData['type'] == 'answer') {
        CallManager.instance.handleAnswer(signalData['data'], () {});
      } else if (signalData['type'] == 'candidate') {
        CallManager.instance.addCandidate(signalData['data']);
      } else if (signalData['type'] == 'hangup') {
        CallManager.instance.stopCall();
      }
    } catch (e) {
      DebugLogger.log('[Call] Signal processing failed | $e', type: 'ERROR');
    }
  }

  void _processIncomingEvent(Map<String, dynamic> event) async {
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

      // Holds the fully-decrypted Rumor when kind==1059, so we can read
      // reply tags and rumor-only metadata from it below.
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
          // For self-envelopes: sender == myPubkey AND rumor p tag == myPubkey
          // would mean this is truly a self-loop with no peer. Skip those.
          // Otherwise the rumor p tag carries the real peer.
          peerPubkey = isFromMe ? receiverPubkey : actualSenderPubkey;
        } catch (e) {
          DebugLogger.log('[NIP-17] Unwrap failed | $e', type: 'ERROR');
          return;
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

      if (peerPubkey.isEmpty || peerPubkey == myPubkey) return;

      // --- Encrypted call signaling (carried inside NIP-17 rumor) ---
      //
      // Call signals are wrapped the same way as chat messages but are
      // marked with a `CALL_SIGNAL:` prefix so we can route them to the
      // CallManager without saving them as chat messages.
      //
      // Ghost-call prevention: NIP-17 events are stored permanently by
      // relays. When the app opens or hot-restarts, the relay replays
      // every event within our sync window (3 days). Without an age
      // check, a `CALL_SIGNAL:offer` from hours ago would trigger a
      // ghost incoming call. The TTL below mirrors the semantics of the
      // existing kind-1000 path (30 s for offers) and adds a state gate
      // so that non-offer signals can only affect an active session.
      if (decrypted.startsWith('CALL_SIGNAL:')) {
        try {
          final signalJson = decrypted.substring('CALL_SIGNAL:'.length);
          final signalData = jsonDecode(signalJson);
          if (signalData is Map) {
            final type = signalData['type']?.toString() ?? '';

            // Offer: 30 s (matches _startConnectionTimeout on the caller).
            // Other signals: 60 s (only affect an already-active session).
            final ttlSec = type == 'offer' ? 30 : 60;
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final ageSec = (nowMs - timestamp) ~/ 1000;

            // Reject stale signals, and also reject signals whose
            // timestamp is implausibly far in the future (clock skew).
            if (ageSec > ttlSec || ageSec < -60) {
              DebugLogger.log(
                '[Call] Stale CALL_SIGNAL ignored '
                    '(type=$type, age=${ageSec}s, ttl=${ttlSec}s)',
              );
              return;
            }

            // Without an active session, only `offer` has meaning.
            // Stale `hangup` / `answer` / `candidate` events arriving
            // while idle would otherwise call stopCall or handleAnswer
            // on an idle CallManager.
            if ((type == 'answer' || type == 'candidate') &&
                CallManager.instance.callState == CallState.idle) {
              DebugLogger.log('[Call] Cold CALL_SIGNAL ignored (type=$type, no active call)');
              return;
            }

            // Reconstruct an event-shaped map so the existing signal
            // handlers (which expect { pubkey, content, created_at })
            // can process it without modification.
            final syntheticEvent = {
              'pubkey': actualSenderPubkey,
              'content': signalJson,
              'created_at': timestamp ~/ 1000,
              'kind': 1059,
              'id': actualEventId,
            };

            // If a call session is active, prefer routing through the
            // CallManager callback — same single-path discipline as the
            // kind-1000 handler.
            if (onSignalReceived != null) {
              try {
                onSignalReceived!(syntheticEvent);
              } catch (e) {
                DebugLogger.log('[Call] onSignalReceived error | $e', type: 'ERROR');
              }
              return;
            }

            // Otherwise, this is a cold-start signal (typically `offer`)
            // that must open the incoming call screen.
            if (actualSenderPubkey != myPubkey) {
              _processCallSignal(syntheticEvent);
            }
          }
        } catch (e) {
          DebugLogger.log('[Call] CALL_SIGNAL parse failed | $e', type: 'ERROR');
        }
        return;
      }

      final chatKey = ChatManager.instance.getChatKey(myPubkey, peerPubkey);

      final bool alreadyExists = await ChatManager.instance.isMessageExists(actualEventId, chatKey);
      if (alreadyExists) return;

      final settingsBox = Hive.box('settings');
      final int cutOffTime = settingsBox.get('cut_off_$peerPubkey', defaultValue: 0);

      if (timestamp <= cutOffTime) return;

      if (decrypted.isEmpty) {
        decrypted = '[Encrypted Message]';
      }

      final bool isFromMe = (actualSenderPubkey == myPubkey);

      // --- Encrypted control messages (carried inside NIP-17 rumor) ---

      // Reaction
      if (decrypted.startsWith('REACTION:')) {
        final parts = decrypted.split(':');
        if (parts.length >= 3) {
          final emoji = parts[1];
          final targetMessageId = parts[2];
          if (targetMessageId.isNotEmpty) {
            await _updateMessageReaction(targetMessageId, actualSenderPubkey, emoji, chatKey);
            if (onMessageReceived != null) onMessageReceived!();
            return;
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
            await ChatManager.instance.updateMessageStatus(
              targetMessageId,
              status,
              chatKey: chatKey,
            );
            if (onMessageReceived != null) onMessageReceived!();
            return;
          }
        }
      }

      // Legacy kind-7 reaction handling (for backwards compat)
      if (event['kind'] == 7) {
        String? targetId;
        for (var t in tags) {
          if (t is List && t.length > 1 && t[0] == 'e') {
            targetId = t[1].toString();
            break;
          }
        }
        if (targetId != null) {
          await _updateMessageReaction(targetId, actualSenderPubkey, content, chatKey);
          if (onMessageReceived != null) onMessageReceived!();
          return;
        }
      }

      // --- Regular chat message ---

      String? replyToId;
      if (event['kind'] == 1059 && nip17Result != null) {
        // Reply tag lives inside the Rumor, already extracted by Nip17.unwrap.
        replyToId = nip17Result.replyToId;
      } else {
        // Legacy NIP-04 / kind-1 path: reply is a public event tag.
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

      await ChatManager.instance.saveMessage(chatMessage);
      await ChatManager.instance.repairReplyContent(actualEventId, decrypted, chatKey);
      await ChatManager.instance.repairPendingReplies(chatKey);
      await _updateContactWithMessage(peerPubkey, decrypted, timestamp, isFromMe, alreadyExists);

      if (onMessageReceived != null) onMessageReceived!();
    } catch (e) {
      DebugLogger.log('[Message] Incoming event error | $e', type: 'ERROR');
    }
  }

  void _handleReceiptEvent(Map<String, dynamic> event) async {
    try {
      final tags = event['tags'] as List? ?? [];
      final senderPubkey = event['pubkey']?.toString() ?? '';
      final myPubkey = AppSettings.instance.myPubkey;

      if (senderPubkey == myPubkey) return;

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

      if (originalMessageId == null || targetP != myPubkey || !isReadStatus) return;

      final chatKey = ChatManager.instance.getChatKey(myPubkey, senderPubkey);
      final message = await ChatManager.instance.getMessageById(originalMessageId, chatKey);

      if (message == null) return;

      if (message.senderPubkey != myPubkey) return;

      await ChatManager.instance.updateMessageStatus(
        originalMessageId,
        'read',
        chatKey: chatKey,
      );

      onMessageReceived?.call();
    } catch (e) {
      DebugLogger.log('[Receipt] Handle error | $e', type: 'ERROR');
    }
  }

  /// Handles relay `["OK", <eventId>, true]` acknowledgements.
  ///
  /// The `<eventId>` here is the **Gift Wrap ID** (kind 1059), because that
  /// is the event we actually published to the relay. We must therefore
  /// look up the ChatMessage by its `giftWrapId` field, not by `id`.
  void _handleOk(List<dynamic> decoded, String url) {
    try {
      if (decoded.length > 2 && decoded[2] == true) {
        final giftWrapId = decoded[1].toString();
        ChatManager.instance.updateMessageStatusByGiftWrap(giftWrapId, 'sent');

        // Pending reactions are processed by the periodic offline queue
        // (_processOfflineQueue, every 15 s). Previously this method also
        // called _processPendingReactions directly, which caused each
        // relay OK to trigger a fresh scan — including the OK emitted in
        // response to a reaction we had just sent, creating an infinite
        // feedback loop that spammed reactions and burned CPU.

        onMessageReceived?.call();
        if (onMessageDelivered != null) onMessageDelivered!(giftWrapId);
      }
    } catch (e) {
      DebugLogger.log('[Relay] OK handler error | $e', type: 'ERROR');
    }
  }

  /// Sends a plaintext message to [receiverPubkey] using NIP-17.
  ///
  /// Two Gift Wraps are produced from a SINGLE Rumor (so both share the
  /// same Rumor ID), then published:
  ///   1. **Recipient envelope** — encrypted to the recipient.
  ///   2. **Self envelope** — encrypted to ourselves, with the recipient
  ///      still referenced in the rumor's `p` tag, so that other devices
  ///      logged into the same account can display the sent message.
  ///
  /// [messageTimestampMs] pins the Rumor's `created_at` to the local
  /// ChatMessage timestamp, so the rumor ID is deterministic and matches
  /// the ID stored on the recipient's side.
  ///
  /// Returns a map with:
  ///   - `giftWrap`: the signed Gift Wrap event (recipient envelope)
  ///   - `giftWrapId`: outer event ID (used for OK matching)
  ///   - `rumorId`: inner Rumor ID (canonical message ID)
  ///   - `rumorTimestamp`: Rumor's original timestamp (ms)
  ///
  /// Throws [Exception] if NIP-17 wrapping fails.
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

      // Build ONE Rumor and wrap it into two envelopes (recipient + self).
      // Both share the same Rumor ID → sender's self-echo dedups cleanly
      // and multi-device sync works.
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

      // Notify via Cloudflare worker (uses recipient Gift Wrap ID)
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
        }),
      ).timeout(const Duration(seconds: 10));

      DebugLogger.log('[Cloudflare] Status ${response.statusCode}');
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

  Future<String?> fetchProfilePicture(String pubkey) async {
    // Return from persistent cache if available
    if (_profilePics.containsKey(pubkey)) {
      final cachedUrl = _profilePics.get(pubkey);
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        return cachedUrl;
      }
    }

    // Wait for relays to connect (max 5 seconds)
    int waitAttempts = 0;
    while (_connectionStatus.values.where((s) => s == true).isEmpty && waitAttempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitAttempts++;
    }

    if (_connectionStatus.values.where((s) => s == true).isEmpty) {
      return null;
    }

    final completer = Completer<String?>();
    final tempSubId = 'profile_${pubkey.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}';

    // Send REQ to all connected relays
    for (final entry in _connections.entries) {
      if (_connectionStatus[entry.key] == true) {
        try {
          final req = jsonEncode(["REQ", tempSubId, {
            "kinds": [0],
            "authors": [pubkey],
            "limit": 1,
          }]);
          entry.value.sink.add(req);
        } catch (e) {
          // Skip failed sends
        }
      }
    }

    // Listen for responses from all relays
    final List<StreamSubscription> subscriptions = [];

    for (final entry in _connections.entries) {
      if (_connectionStatus[entry.key] == true) {
        final sub = entry.value.stream.listen((data) {
          try {
            final decoded = jsonDecode(data.toString());
            if (decoded is List && decoded.length > 2 && decoded[0] == "EVENT") {
              final rawEvent = decoded[2];
              if (rawEvent is! Map) return;
              final event = rawEvent as Map<String, dynamic>;
              if (event['kind'] == 0 && event['pubkey'] == pubkey) {
                final rawContent = event['content'];
                if (rawContent is String && rawContent.trim().startsWith('{')) {
                  final content = jsonDecode(rawContent);
                  if (content is Map<String, dynamic>) {
                    final picture = content['picture'] is String ? content['picture'] as String : null;

                    if (picture != null && picture.isNotEmpty && !completer.isCompleted) {
                      // Simpan ke Hive tanpa await (fire-and-forget)
                      _profilePics.put(pubkey, picture).then((_) {
                        if (!completer.isCompleted) {
                          completer.complete(picture);
                        }
                      });
                    }
                  }
                }
              }
            }
          } catch (e) {
            // Ignore parsing errors
          }
        });
        subscriptions.add(sub);
      }
    }

    // Timeout after 8 seconds
    final timeout = Timer(const Duration(seconds: 8), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    final result = await completer.future;
    timeout.cancel();

    // Cleanup
    for (final sub in subscriptions) {
      sub.cancel();
    }

    for (final entry in _connections.entries) {
      if (_connectionStatus[entry.key] == true) {
        try {
          entry.value.sink.add(jsonEncode(["CLOSE", tempSubId]));
        } catch (_) {}
      }
    }

    return result;
  }

  /// Generate NIP-98 authentication token for nostr.build
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

      // Perbarui cache lokal untuk diri sendiri
      if (photoUrl != null && photoUrl.isNotEmpty) {
        _profilePics.put(myPubkey, photoUrl);
      } else {
        _profilePics.delete(myPubkey);
      }
      // Trigger pembaruan UI
      onMessageReceived?.call();
    } catch (e) {
      DebugLogger.log('[Profile] Broadcast kind 0 failed | $e', type: 'ERROR');
    }
  }

  /// Sends a read receipt for [originalRumorId] to [receiverPubkey].
  ///
  /// The receipt is wrapped as a NIP-17 message (Rumor -> Seal -> Gift Wrap)
  /// so that relay operators cannot see who is reading whose messages.
  /// The plaintext payload is `READ_RECEIPT:<rumorId>:<status>`.
  ///
  /// [originalRumorId] MUST be the canonical Rumor ID of the message being
  /// acknowledged (i.e. `ChatMessage.id`), NOT the Gift Wrap ID.
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

  /// Sends a reaction emoji for [messageId] to [receiverPubkey].
  ///
  /// The reaction is wrapped as a NIP-17 message. [messageId] MUST be the
  /// canonical Rumor ID of the message being reacted to (`ChatMessage.id`).
  ///
  /// Returns `true` if successfully sent to at least one connected relay,
  /// `false` otherwise (e.g. offline).
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

      // Single Rumor shared across both envelopes, so the reaction lands
      // on the same message ID on both sides.
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

  /// Sends a WebRTC signaling payload to [recipientPubkey], encrypted via
  /// NIP-17.
  ///
  /// The signal JSON is prefixed with `CALL_SIGNAL:` and wrapped as a
  /// NIP-17 Rumor -> Seal -> Gift Wrap. Relay operators cannot see the
  /// SDP (codec, media parameters) or any ICE candidates that may be
  /// embedded in the SDP.
  ///
  /// Because the caller uses vanilla-ICE mode, each signal is a single
  /// bundle containing the full SDP with candidates already embedded.
  /// A call therefore consists of ~4 signals instead of ~30.
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
    } catch (e) {
      DebugLogger.log('[Call] Send signal failed | $e', type: 'ERROR');
    }
  }

  Future<void> _updateContactWithMessage(String peerPubkey, String message, int timestamp, bool isFromMe, bool alreadyExists) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      Contact? contact = contactsBox.get(peerPubkey);

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
    } catch (e) {
      DebugLogger.log('[Contact] Update failed | $e', type: 'ERROR');
    }
  }

  Future<void> _updateMessageReaction(
      String messageId,
      String reactorPubkey,
      String emoji,
      String chatKey
      ) async {
    try {
      final box = Hive.box('chats');
      final dynamic raw = box.get(chatKey);
      if (raw is! List) return;

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

        // Notify UI
        if (onMessageReceived != null) onMessageReceived!();
      } else {
        DebugLogger.log('[Reaction] Target message not found: $messageId', type: 'WARN');
      }
    } catch (e) {
      DebugLogger.log('[Reaction] Update failed | $e', type: 'ERROR');
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

  void _startPingTimer(String url, WebSocketChannel ch) {
    _pingTimers[url]?.cancel();
    _pingTimers[url] = Timer.periodic(const Duration(seconds: 30), (t) {
      if (_connectionStatus[url] == true) {
        try {
          ch.sink.add(jsonEncode(["PING", "p"]));
        } catch (e) {
          t.cancel();
        }
      }
    });
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (t) {
      if (_processedEventIds.length > 5000) {
        final list = _processedEventIds.toList();
        _processedEventIds.clear();
        _processedEventIds.addAll(list.sublist(list.length - 1000));
      }
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
        _connectToRelay(url, AppSettings.instance.myPubkey);
      }
    });
  }

  void _updateConnectionStatus() {
    final count = _connectionStatus.values.where((s) => s == true).length;
    final bool wasConnected = _isConnected.value;
    final bool isNowConnected = count > 0;

    _isConnected.value = isNowConnected;
    _connectedCount.value = count;

    // Trigger the offline queue only on the transition from
    // disconnected → connected. Without this guard, every relay that
    // connects (six of them, arriving nearly simultaneously) would
    // fire its own queue-processing pass, causing a CPU spike.
    if (!wasConnected && isNowConnected) {
      _processOfflineQueue();
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
        // Re-fetch from Hive — replyToId may have been updated by a previous iteration
        final msg = await ChatManager.instance.getMessageById(snapshot.id, snapshot.chatKey);
        if (msg == null) continue;
        if (msg.status == 'sent' || msg.status == 'read') continue;

        // Cooldown: skip if we tried to send this message < 60s ago.
        final lastAttempt = _lastQueueAttempt[msg.id] ?? 0;
        if (nowMs - lastAttempt < 60000) continue;
        _lastQueueAttempt[msg.id] = nowMs;

        final myPrivkey = AppSettings.instance.myPrivkey;
        final myPubkey = AppSettings.instance.myPubkey;
        final plaintext = msg.plaintext.isNotEmpty ? msg.plaintext : msg.content;
        if (plaintext.isEmpty) continue;

        try {
          // Force the Rumor timestamp to the ORIGINAL message timestamp so
          // re-sends produce the same Rumor ID — this keeps the message
          // idempotent on the recipient's side, and keeps reactions and
          // read receipts pointing at a stable ID.
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

      // Process pending reactions after queue processing
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
          // REQUISITE: Message must be confirmed sent or read (OK received from relay)
          // and have a final valid ID (not temp_ or pending_)
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