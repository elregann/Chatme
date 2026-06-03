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
import 'package:http/http.dart' as http;

class RelayManager {
  Function? onMessageReceived;
  String? currentlyChattingWith;

  Function(Map<String, dynamic>)? onSignalReceived;

  final List<String> relays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://nostr.mom',
    'wss://relay.primal.net',
    'wss://relay.mostr.pub',
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
      DebugLogger.log('❌ Error handling data: $e');
    }
  }

  Future<void> _handleEvent(List<dynamic> decoded, String url) async {
    final event = decoded[2] as Map<String, dynamic>;
    final eventId = event['id']?.toString() ?? '';
    final kind = event['kind'] as int? ?? 0;
    final createdAt = event['created_at'] as int? ?? 0;

    // Cache profile picture from kind 0 events
    if (kind == 0) {
      final pubkey = event['pubkey'] as String?;
      if (pubkey != null) {
        try {
          final content = jsonDecode(event['content'] as String);
          final picture = content['picture'] as String?;
          if (picture != null && picture.isNotEmpty) {
            _profilePics.put(pubkey, picture);
          } else {
            // Hapus cache jika foto dihapus
            _profilePics.delete(pubkey);
          }
          // Beri tahu UI untuk rebuild
          onMessageReceived?.call();
        } catch (e) {
          // Ignore parsing errors
        }
      }
    }

    if (eventId.isEmpty || _processedEventIds.contains(eventId)) return;

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final myPubkey = AppSettings.instance.myPubkey;
    final senderPubkey = event['pubkey']?.toString() ?? '';

    if (kind == 1000) {
      try {
        if (onSignalReceived != null) onSignalReceived!(event);
      } catch (e) {
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
        String finalDisplayName = AppSettings.formatDisplayName(callerPubkey);
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
      } else if (event['kind'] == 7) {
        String? targetId;
        for (var t in tags) {
          if (t is List && t.length > 1 && t[0] == 'e') {
            targetId = t[1].toString();
            break;
          }
        }
        if (targetId != null) {
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
      String? replyToSenderPubkey;
      if (replyToId != null) {
        final originalMsg = await ChatManager.instance.getMessageById(replyToId, chatKey);
        replyToContent = originalMsg?.plaintext;
        replyToSenderPubkey = originalMsg?.senderPubkey;
      }

      final String initialStatus = isFromMe ? 'sending' : 'sent';

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
        replyToSenderPubkey: replyToSenderPubkey,
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

      // Ambil nama pengirim dari contacts
      final contactsBox = Hive.box<Contact>('contacts');
      final myContact = contactsBox.get(myPubkey);
      final senderName = (myContact != null && myContact.isSaved)
          ? myContact.name
          : AppSettings.formatDisplayName(myPubkey);

      // Trigger notifikasi via Cloudflare
      _triggerCloudflareNotification(
        receiverPubkey: receiverPubkey,
        senderPubkey: myPubkey,
        eventId: eventId,
        senderName: senderName,
        ciphertext: encryptedContent,
      );
      return signedEvent;

    } catch (e) {
      DebugLogger.log('❌ ERROR in sendMessage: $e', type: 'ERROR');
      rethrow;
    }
  }

  void _triggerCloudflareNotification({
    required String receiverPubkey,
    required String senderPubkey,
    required String eventId,
    required String senderName,
    required String ciphertext,
  }) async {
    const workerUrl = 'https://chatme-notifier.ismaelurzaizaranda.workers.dev/';
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
        }),
      ).timeout(const Duration(seconds: 10));

      DebugLogger.log('🚀 Cloudflare Status: ${response.statusCode}');
      DebugLogger.log('📦 Cloudflare Response: ${response.body}');
    } catch (e) {
      DebugLogger.log('⚠️ Cloudflare error: $e');
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
            if (decoded is List && decoded[0] == "EVENT") {
              final event = decoded[2] as Map<String, dynamic>;
              if (event['kind'] == 0 && event['pubkey'] == pubkey) {
                final content = jsonDecode(event['content'] as String);
                final picture = content['picture'] as String?;

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
      DebugLogger.log('❌ Cannot generate NIP-98 token: missing keys');
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

    DebugLogger.log('🔑 Generated NIP-98 token (length: ${token.length})');

    return 'Nostr $token';
  }

  Future<String?> uploadPhotoToNostrBuild(String filePath) async {
    if (kIsWeb) {
      DebugLogger.log('❌ Photo upload not supported in web environment');
      return null;
    }

    try {
      final uploadUrl = Uri.parse('https://nostr.build/api/v2/upload/files');
      final token = _generateNip98Token(uploadUrl.toString(), 'POST');
      if (token.isEmpty) {
        DebugLogger.log('❌ NIP-98 token empty, upload aborted');
        return null;
      }

      final request = http.MultipartRequest('POST', uploadUrl);
      request.headers['Authorization'] = token;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final response = await request.send().timeout(const Duration(seconds: 30));
      final body = jsonDecode(await response.stream.bytesToString());

      if (response.statusCode == 200) {
        final url = body['data']?[0]?['url'] as String?;
        DebugLogger.log('✅ Photo uploaded: $url');
        return url;
      }
      DebugLogger.log('❌ Upload failed: $body');
      return null;
    } catch (e) {
      DebugLogger.log('❌ Upload error: $e');
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

      DebugLogger.log('✅ Kind 0 broadcasted');
    } catch (e) {
      DebugLogger.log('❌ Error broadcasting kind 0: $e');
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