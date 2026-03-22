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
import 'core/crypto/nostr_protocol.dart';
import 'services/app_settings.dart';
import 'models/contact.dart';
import 'core/utils/debug_logger.dart';
import 'models/chat_message.dart';
import 'services/nostr_service.dart';

class RelayManager {
  Function? onMessageReceived;
  String? currentlyChattingWith;

  Function(Map<String, dynamic>)? onSignalReceived;

  final List<String> relays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.snort.social',
  ];

  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, bool> _connectionStatus = {};
  final Map<String, Timer> _pingTimers = {};
  final Map<String, int> _reconnectAttempts = {};
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
        _queueTimer = Timer.periodic(const Duration(seconds: 60), (t) {
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
      _reconnectAttempts[relayUrl] = 0;

      await Future.delayed(const Duration(milliseconds: 100));

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
            syncSince = (latestTime ~/ 1000) - 3600;
            DebugLogger.log('🔄 Sync dinamis aktif: Menarik sejak ${DateTime.fromMillisecondsSinceEpoch(syncSince * 1000)}');
          }
        }
      } catch (e) {
        DebugLogger.log('⚠️ Gagal hitung syncSince, gunakan default 30 hari.');
      }

      final List<int> neededKinds = [1, 4, 7, 1000];

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

      _startPingTimer(relayUrl, channel);

      channel.stream.listen(
            (data) {
          _connectionStatus[relayUrl] = true;
          _updateConnectionStatus();
          _handleData(data, relayUrl);
        },
        onError: (e) => _handleError(relayUrl, e),
        onDone: () => _handleDisconnect(relayUrl),
        cancelOnError: true,
      );
    } catch (e) {
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
      DebugLogger.log('❌ Error closing connection: $e');
    }
  }

  void _handleData(dynamic data, String url) {
    try {
      final message = data.toString();
      if (message.contains('"EOSE"') || message.contains('"PONG"')) return;

      final decoded = jsonDecode(message);
      if (decoded is List && decoded.length > 2) {
        if (decoded[0] == "EVENT") _handleEvent(decoded, url);
        if (decoded[0] == "OK") _handleOk(decoded, url);
      }
    } catch (e) {
      DebugLogger.log('❌ Error handling data: $e');
    }
  }

  void _handleEvent(List<dynamic> decoded, String url) {
    final event = decoded[2] as Map<String, dynamic>;
    final eventId = event['id']?.toString() ?? '';
    final kind = event['kind'] as int? ?? 0;
    final createdAt = event['created_at'] as int? ?? 0;

    if (eventId.isEmpty || _processedEventIds.contains(eventId)) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final myPubkey = AppSettings.instance.myPubkey;
    final senderPubkey = event['pubkey']?.toString() ?? '';

    if (kind == 1000) {
      try { if (onSignalReceived != null) onSignalReceived!(event); } catch (e) {
        DebugLogger.log('❌ Error onSignalReceived: $e');
      }
      if (senderPubkey == myPubkey) return;
      if (now - createdAt > 30) return;

      _processedEventIds.add(eventId);
      _processCallSignal(event);
      return;
    }

    if (kind == 1 || kind == 4 || kind == 7) {

      if (kind == 7) {
        if (senderPubkey == myPubkey) return;
        if (now - createdAt > 60) return;
      }

      _processedEventIds.add(eventId);

      if (kind == 1 || kind == 4) {
        _processIncomingEvent(event);
      }

      if (kind == 7) _handleReceiptEvent(event);
    }
  }

  void _processCallSignal(Map<String, dynamic> event) {
    try {
      final signalData = jsonDecode(event['content']);
      final callerPubkey = event['pubkey'];

      if (signalData['type'] == 'offer') {
        String finalDisplayName = "User ${callerPubkey.substring(0, 8)}";
        try {
          final contactBox = Hive.box<Contact>('contacts');
          final savedContact = contactBox.get(callerPubkey);
          if (savedContact != null && savedContact.isSaved) {
            finalDisplayName = savedContact.name;
          }
        } catch (e) {
          DebugLogger.log('❌ Gagal memuat kontak: $e');
        }

        final Color incomingPeerColor = Color(
            int.parse(callerPubkey.substring(0, 8), radix: 16) | 0xFF000000
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
      DebugLogger.log('❌ Gagal proses sinyal: $e');
    }
  }

  void _processIncomingEvent(Map<String, dynamic> event) async {
    try {
      final eventId = event['id']?.toString() ?? '';
      final senderPubkey = event['pubkey']?.toString() ?? '';
      final myPubkey = AppSettings.instance.myPubkey;
      final tags = event['tags'] as List? ?? [];
      final receiverPubkey = _extractReceiverPubkey(tags);
      final bool isFromMe = (senderPubkey == myPubkey);
      final String peerPubkey = isFromMe ? receiverPubkey : senderPubkey;

      if (peerPubkey.isEmpty || peerPubkey == myPubkey) return;

      final chatKey = ChatManager.instance.getChatKey(myPubkey, peerPubkey);

      final bool alreadyExists = await ChatManager.instance.isMessageExists(eventId, chatKey);
      if (alreadyExists) return;

      final settingsBox = Hive.box('settings');
      final int cutOffTime = settingsBox.get('cut_off_$peerPubkey', defaultValue: 0);
      final int timestamp = (event['created_at'] as int? ?? 0) * 1000;

      if (timestamp <= cutOffTime) return;

      final content = event['content']?.toString() ?? '';
      final myPrivkey = AppSettings.instance.myPrivkey;

      String decrypted = Nip04.decrypt(
        content,
        myPrivkey,
        peerPubkey,
      );

      if (decrypted.isEmpty) {
        if (event['kind'] == 1) {
          decrypted = content;
        } else {
          decrypted = '[Encrypted Message]';
        }
      }

      if (decrypted.startsWith('REACTION:')) {
        final parts = decrypted.split(':');
        if (parts.length >= 3) {
          final emoji = parts[1];
          final targetMessageId = parts[2];
          if (targetMessageId.isNotEmpty) {
            await _updateMessageReaction(targetMessageId, senderPubkey, emoji, chatKey);
            if (onMessageReceived != null) onMessageReceived!();
            return;
          }
        }
      }

      else if (event['kind'] == 7) {
        String? targetId;
        for (var t in tags) {
          if (t is List && t.length > 1 && t[0] == 'e') {
            targetId = t[1].toString();
            break;
          }
        }
        if (targetId != null) {
          // Pada Kind 7, emoji ada di 'content'
          await _updateMessageReaction(targetId, senderPubkey, content, chatKey);
          if (onMessageReceived != null) onMessageReceived!();
          return;
        }
      }

      String? replyToId;
      for (var t in tags) {
        if (t is List && t.length > 1 && t[0] == 'e') {
          replyToId = t[1].toString();
          break;
        }
      }

      String? replyToContent;
      if (replyToId != null) {
        final originalMsg = await ChatManager.instance.getMessageById(replyToId, chatKey);
        replyToContent = originalMsg?.plaintext;
      }

      String initialStatus;
      if (isFromMe) {
        initialStatus = 'sending';
      } else {
        initialStatus = 'sent';
      }

      final chatMessage = ChatMessage(
        id: eventId,
        senderPubkey: senderPubkey,
        receiverPubkey: receiverPubkey,
        content: content,
        plaintext: decrypted,
        timestamp: timestamp,
        status: initialStatus,
        chatKey: chatKey,
        replyToId: replyToId,
        replyToContent: replyToContent,
      );

      await ChatManager.instance.saveMessage(chatMessage);
      await ChatManager.instance.repairReplyContent(eventId, decrypted, chatKey);
      await _updateContactWithMessage(peerPubkey, decrypted, timestamp, isFromMe, alreadyExists);

      if (onMessageReceived != null) onMessageReceived!();
    } catch (e) {
      DebugLogger.log('❌ Error processing incoming event: $e');
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
      DebugLogger.log('❌ Error in _handleReceiptEvent: $e');
    }
  }

  void _handleOk(List<dynamic> decoded, String url) {
    try {
      if (decoded.length > 2 && decoded[2] == true) {
        final messageId = decoded[1].toString();
        ChatManager.instance.updateMessageStatus(messageId, 'sent');

        onMessageReceived?.call();
        if (onMessageDelivered != null) onMessageDelivered!(messageId);
      }
    } catch (e) {
      DebugLogger.log('❌ Error in _handleOk: $e');
    }
  }

  Future<Map<String, dynamic>> sendMessage({
    required String receiverPubkey,
    required String plaintext,
    String? replyToId,
    String? replyToContent,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) {
        DebugLogger.log('❌ ERROR: Missing keys in sendMessage', type: 'ERROR');
        throw Exception('Missing pubkey or privkey');
      }

      final encryptedContent = Nip04.encrypt(
        plaintext,
        myPrivkey,
        receiverPubkey,
      );

      if (encryptedContent.isEmpty) {
        throw Exception('Encryption failed');
      }

      final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final List<List<String>> tags = [['p', receiverPubkey]];

      if (replyToId != null && replyToId.isNotEmpty) {
        tags.add(['e', replyToId]);
      }

      final unsignedEvent = {
        'pubkey': myPubkey,
        'created_at': createdAt,
        'kind': 4,
        'tags': tags,
        'content': encryptedContent,
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);

      if (eventId.isEmpty) {
        throw Exception('Event ID generation failed');
      }

      final signature = NostrSigner.sign(eventId, myPrivkey);

      if (signature.isEmpty) {
        throw Exception('Signature generation failed');
      }

      final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", signedEvent]));
        }
      }

      final chatMessage = ChatMessage(
        id: eventId,
        senderPubkey: myPubkey,
        receiverPubkey: receiverPubkey,
        content: encryptedContent,
        plaintext: plaintext,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'sending',
        chatKey: ChatManager.instance.getChatKey(myPubkey, receiverPubkey),
        replyToId: replyToId,
        replyToContent: replyToContent,
      );

      await ChatManager.instance.saveMessage(chatMessage);
      return signedEvent;
    } catch (e) {
      DebugLogger.log('❌ ERROR in sendMessage: $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> sendReceipt(String originalEventId, String receiverPubkey, String status) async {
    try {
      final myPrivkey = AppSettings.instance.myPrivkey;
      final myPubkey = AppSettings.instance.myPubkey;

      final unsignedEvent = {
        'pubkey': myPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 7,
        'tags': [['e', originalEventId], ['p', receiverPubkey], ['status', status]],
        'content': status == 'read' ? '👁️' : '✓',
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);
      final signature = NostrSigner.sign(eventId, myPrivkey);
      final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};

      for (final conn in _connections.values) {
        conn.sink.add(jsonEncode(["EVENT", signedEvent]));
      }
    } catch (e) {
      DebugLogger.log('❌ Error sendReceipt: $e');
    }
  }

  Future<void> sendReaction({
    required String messageId,
    required String receiverPubkey,
    required String emoji,
  }) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;

      final reactionPlaintext = 'REACTION:$emoji:$messageId';

      final encryptedContent = Nip04.encrypt(
        reactionPlaintext,
        myPrivkey,
        receiverPubkey,
      );
      if (encryptedContent.isEmpty) return;

      final unsignedEvent = {
        'pubkey': myPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 4,
        'tags': [
          ['p', receiverPubkey],
          ['e', messageId],
        ],
        'content': encryptedContent,
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);
      final signature = NostrSigner.sign(eventId, myPrivkey);
      final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", signedEvent]));
        }
      }

      DebugLogger.log('✅ Reaction sent to relay: $emoji');
    } catch (e) {
      DebugLogger.log('❌ Error sendReaction: $e');
    }
  }

  Future<void> sendCallSignal(String recipientPubkey, Map<String, dynamic> signalData) async {
    try {
      final myPubkey = AppSettings.instance.myPubkey;
      final myPrivkey = AppSettings.instance.myPrivkey;

      if (myPubkey.isEmpty || myPrivkey.isEmpty) return;

      final Map<String, dynamic> unsignedEvent = {
        'pubkey': myPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 1000,
        'tags': [['p', recipientPubkey]],
        'content': jsonEncode(signalData),
      };

      final eventId = NostrHelpers.generateEventId(unsignedEvent);
      final signature = NostrSigner.sign(eventId, myPrivkey);
      final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};

      for (final entry in _connections.entries) {
        if (_connectionStatus[entry.key] == true) {
          entry.value.sink.add(jsonEncode(["EVENT", signedEvent]));
        }
      }
    } catch (e) {
      DebugLogger.log('❌ Error sendCallSignal: $e');
    }
  }

  Future<void> _updateContactWithMessage(String peerPubkey, String message, int timestamp, bool isFromMe, bool alreadyExists) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      Contact? contact = contactsBox.get(peerPubkey);

      if (contact == null) {
        contact = Contact(
            pubkey: peerPubkey,
            name: 'User ${peerPubkey.substring(0, 8)}',
            lastChatTime: timestamp,
            lastMessage: message,
            unreadCount: (isFromMe || currentlyChattingWith == peerPubkey || alreadyExists) ? 0 : 1,
            isSaved: false
        );
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
      DebugLogger.log('❌ Error updating contact: $e');
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

        DebugLogger.log('✅ Reaction received: $emoji from $reactorPubkey on message $messageId');

        // Notify UI
        if (onMessageReceived != null) onMessageReceived!();
      } else {
        DebugLogger.log('⚠️ Original message not found for reaction: $messageId');
      }
    } catch (e) {
      DebugLogger.log('❌ Error updating message reaction: $e');
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
    final attempts = _reconnectAttempts[url] ?? 0;
    if (attempts > 10) return;

    final delay = Duration(seconds: min(5 * (1 << attempts), 60));
    Future.delayed(delay, () {
      if (_connections.containsKey(url) && _connectionStatus[url] == false) {
        _reconnectAttempts[url] = attempts + 1;
        _connectToRelay(url, AppSettings.instance.myPubkey);
      }
    });
  }

  void _updateConnectionStatus() {
    final count = _connectionStatus.values.where((s) => s == true).length;
    _isConnected.value = count > 0;
    _connectedCount.value = count;
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

    final pendingMessages = await ChatManager.instance.getPendingMessages();
    if (pendingMessages.isEmpty) return;

    _isProcessingQueue = true;
    DebugLogger.log('🚀 Memproses ${pendingMessages.length} pesan antrean...');

    try {
      for (var msg in pendingMessages) {
        final List<List<String>> tags = [['p', msg.receiverPubkey]];
        if (msg.replyToId != null) {
          tags.add(['e', msg.replyToId!]);
        }

        final int createdAt = msg.timestamp ~/ 1000;

        final event = {
          'pubkey': msg.senderPubkey,
          'created_at': createdAt,
          'kind': 4,
          'tags': tags,
          'content': msg.content,
        };

        final String finalId = NostrSigner.calculateEventId(event);
        event['id'] = finalId;
        event['sig'] = NostrSigner.sign(finalId, AppSettings.instance.myPrivkey);

        bool sentToAtLeastOne = false;
        for (final entry in _connections.entries) {
          if (_connectionStatus[entry.key] == true) {
            entry.value.sink.add(jsonEncode(["EVENT", event]));
            sentToAtLeastOne = true;
          }
        }

        if (sentToAtLeastOne) {
          await ChatManager.instance.updateMessageIdAndStatus(
              msg.id,
              finalId,
              'sent',
              msg.chatKey
          );
          DebugLogger.log('✅ Berhasil kirim antrean & Update ID: $finalId');
        }

        await Future.delayed(const Duration(milliseconds: 800));
      }
    } catch (e) {
      DebugLogger.log('❌ Gagal di antrean: $e');
    } finally {
      _isProcessingQueue = false;
    }
  }
}