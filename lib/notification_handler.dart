// notification_handler.dart

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'chat_manager.dart';
import 'core/crypto/nip04.dart';

/// Background FCM handler (runs in separate isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await Hive.initFlutter();

  final senderPubkey = message.data['senderPubkey'] ?? '';
  final senderName = message.data['senderName'] ?? 'New Message';
  final ciphertext = message.data['ciphertext'] ?? '';
  final eventId = message.data['eventId'] ?? '';

  if (senderPubkey.isEmpty || eventId.isEmpty) return;

  final settingsBox = await Hive.openBox('settings');
  final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;

  String plaintext = 'You have a new message';
  if (ciphertext.isNotEmpty && myPrivkey.isNotEmpty) {
    try {
      final decrypted = Nip04.decrypt(ciphertext, myPrivkey, senderPubkey);
      if (decrypted.isNotEmpty) plaintext = decrypted;
    } catch (_) {}
  }

  // Mark as notified so the foreground handler does not duplicate
  await settingsBox.put('notified_$eventId', true);

  await NotificationHandler.showChatNotification(
    senderPubkey: senderPubkey,
    senderName: senderName,
    message: plaintext,
    showActions: false,
  );
}

@pragma('vm:entry-point')
class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // Streams
  static final StreamController<String?> onNotificationClick =
  StreamController<String?>.broadcast();

  static final StreamController<Map<String, String>> onNotificationReply =
  StreamController<Map<String, String>>.broadcast();

  // In-memory message history per contact (for MessagingStyle stacking)
  static final Map<String, List<Map<String, String>>> _messageHistory = {};

  // Callback registry
  static void Function(String senderPubkey, String replyText)? onReplyCallback;

  // Channel & action constants
  static const String _channelId = 'chat_me_urgent_channel';
  static const String _channelName = 'Messages & Calls';
  static const String _channelDescription = 'Notifications for chats and calls';
  static const String _replyActionId = 'REPLY_ACTION';
  static const String _markReadActionId = 'MARK_READ_ACTION';

  // Notification grouping (all chat notifications share a single group)
  static const String _groupKey = 'chatme_chat_group';
  static const int _summaryNotificationId = 999999;

  // Track FCM subscriptions and init state
  static final List<StreamSubscription> _fcmSubscriptions = [];
  static bool _initialized = false;

  /// Pubkey of the chat room currently open. Used to suppress notifications
  /// for messages from that peer when the app is in foreground.
  static String? activeChatPubkey;

  /// Returns true if a notification from this sender should be suppressed
  /// because the user is already viewing the chat in foreground.
  static bool _shouldSuppressNotification(String senderPubkey) {
    if (activeChatPubkey == null) return false;
    if (senderPubkey != activeChatPubkey) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return state == AppLifecycleState.resumed;
  }

  /// Initialize notification handler. Safe to call multiple times.
  static Future<void> init({dynamic relayManager}) async {
    if (kIsWeb) {
      debugPrint('[Notification] Web platform: mobile notifications skipped');
      return;
    }

    if (_initialized) {
      debugPrint('[Notification] Already initialized, skipping');
      return;
    }

    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Request permissions
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // iOS: show banner + sound while app is in foreground
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Setup local notification plugin
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
      );

      // Create notification channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Foreground FCM: display as local notification
      _fcmSubscriptions.add(
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage),
      );

      // App resumed from background via notification tap
      _fcmSubscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          final senderPubkey = message.data['senderPubkey'] ?? '';
          if (senderPubkey.isNotEmpty) {
            onNotificationClick.add(senderPubkey);
          }
        }),
      );

      // App launched from killed state via notification tap
      final RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final senderPubkey = initialMessage.data['senderPubkey'] ?? '';
        if (senderPubkey.isNotEmpty) {
          onNotificationClick.add(senderPubkey);
        }
      }

      // Wire up reply callback
      if (relayManager != null) {
        onReplyCallback = (senderPubkey, replyText) async {
          relayManager.connectIfNeeded();
          await Future.delayed(const Duration(milliseconds: 800));
          await ChatManager.sendReplyFromNotification(
            receiverPubkey: senderPubkey,
            plaintext: replyText,
            relayManager: relayManager,
          );
        };
      }

      final String? token = await messaging.getToken();
      _initialized = true;
      debugPrint('[Notification] Initialized. FCM token: ${token != null ? "OK" : "MISSING"}');
    } catch (e) {
      debugPrint('[Notification] Init failed | $e');
    }
  }

  /// Handle foreground FCM message.
  static void _handleForegroundMessage(RemoteMessage message) {
    final senderPubkey = message.data['senderPubkey'] ?? '';
    final senderName = message.data['senderName'] ?? 'New Message';
    final body = message.notification?.body ?? message.data['body'] ?? '';

    if (senderPubkey.isNotEmpty && body.isNotEmpty) {
      showChatNotification(
        senderPubkey: senderPubkey,
        senderName: senderName,
        message: body,
      );
    }
  }

  /// Notification tap or action button pressed (foreground).
  @pragma('vm:entry-point')
  static void _onNotificationResponse(NotificationResponse response) {
    final SendPort? sendPort = IsolateNameServer.lookupPortByName('chatme_notification_port');
    if (sendPort != null) {
      sendPort.send({
        'actionId': response.actionId,
        'input': response.input,
        'payload': response.payload,
      });
    }
  }

  /// Background action button handler.
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    _onNotificationResponse(response);
  }

  /// Stable notification ID derived from pubkey (survives app restarts).
  static int _notificationId(String pubkey) {
    final digest = sha256.convert(utf8.encode(pubkey)).bytes;
    return ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]).abs() % 1000000;
  }

  /// Show a chat notification with MessagingStyle stacking.
  static Future<void> showChatNotification({
    required String senderPubkey,
    required String senderName,
    required String message,
    bool showActions = true,
  }) async {
    // Suppress if user is already viewing this chat in foreground
    if (_shouldSuppressNotification(senderPubkey)) {
      return;
    }

    // Append to history for this contact
    final history = _messageHistory.putIfAbsent(senderPubkey, () => []);
    history.add({
      'sender': senderName,
      'message': message,
      'time': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // Cap history at 10 messages per contact
    if (history.length > 10) {
      history.removeAt(0);
    }

    // Build MessagingStyle messages
    final List<Message> styleMessages = history
        .map((m) => Message(
      m['message']!,
      DateTime.fromMillisecondsSinceEpoch(int.parse(m['time']!)),
      Person(name: m['sender']!, key: senderPubkey, important: false),
    ))
        .toList();

    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
      const Person(name: 'You', key: 'me'),
      conversationTitle: senderName,
      groupConversation: false,
      messages: styleMessages,
    );

    // Action: inline reply
    const AndroidNotificationAction replyAction = AndroidNotificationAction(
      _replyActionId,
      'Reply',
      inputs: [AndroidNotificationActionInput(label: 'Type a message...')],
      showsUserInterface: false,
      cancelNotification: false,
    );

    // Action: mark as read
    const AndroidNotificationAction markReadAction = AndroidNotificationAction(
      _markReadActionId,
      'Mark as Read',
      cancelNotification: true,
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      styleInformation: messagingStyle,
      actions: showActions ? [replyAction, markReadAction] : [],
      groupKey: _groupKey,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
      ongoing: false,
      onlyAlertOnce: false,
    );

    final NotificationDetails details = NotificationDetails(android: androidDetails);
    final int notifId = _notificationId(senderPubkey);

    try {
      await _plugin.show(notifId, senderName, message, details, payload: senderPubkey);
      await _showSummaryIfNeeded();
    } catch (e) {
      debugPrint('[Notification] Show failed | $e');
    }
  }

  /// Show or update the group summary notification.
  static Future<void> _showSummaryIfNeeded() async {
    final activeCount = _messageHistory.length;
    if (activeCount < 2) return;

    final total = _messageHistory.values.fold<int>(0, (sum, list) => sum + list.length);

    const AndroidNotificationDetails summaryDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      groupKey: _groupKey,
      setAsGroupSummary: true,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    try {
      await _plugin.show(
        _summaryNotificationId,
        'ChatMe',
        '$total new messages from $activeCount conversation${activeCount > 1 ? "s" : ""}',
        const NotificationDetails(android: summaryDetails),
      );
    } catch (e) {
      debugPrint('[Notification] Summary show failed | $e');
    }
  }

  /// Dismiss notification for a specific contact.
  static Future<void> clearNotification(String senderPubkey) async {
    final int notifId = _notificationId(senderPubkey);
    await _plugin.cancel(notifId);
    _messageHistory.remove(senderPubkey);

    if (_messageHistory.length < 2) {
      await _plugin.cancel(_summaryNotificationId);
    } else {
      await _showSummaryIfNeeded();
    }
  }

  /// Dismiss all chat notifications.
  static Future<void> clearAllNotifications() async {
    await _plugin.cancelAll();
    _messageHistory.clear();
  }

  /// Simple notification for calls / non-chat events.
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      autoCancel: true,
      icon: '@mipmap/ic_launcher',
    );

    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[Notification] Show simple failed | $e');
    }
  }
}