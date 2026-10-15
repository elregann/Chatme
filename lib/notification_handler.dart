// notification_handler.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'chat_manager.dart';
import 'chat_notification_handler.dart' as chat_notif;
import 'call_notification_handler.dart';

// Re-export background handler so entry-point works correctly
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  return await chat_notif.firebaseMessagingBackgroundHandler(message);
}

@pragma('vm:entry-point')
class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // Streams
  static final StreamController<String?> onNotificationClick =
  StreamController<String?>.broadcast();

  static final StreamController<Map<String, String>> onNotificationReply =
  StreamController<Map<String, String>>.broadcast();

  // Callback registry
  static void Function(String senderPubkey, String replyText)? onReplyCallback;

  // Channel & action constants
  static const String _channelId = chat_notif.ChatNotificationHandler.channelId;
  static const String _channelName = chat_notif.ChatNotificationHandler.channelName;
  static const String _channelDescription = chat_notif.ChatNotificationHandler.channelDescription;

  // Track FCM subscriptions and init state
  static final List<StreamSubscription> _fcmSubscriptions = [];
  static bool _initialized = false;

  /// Pubkey of the chat room currently open.
  static String? get activeChatPubkey => chat_notif.ChatNotificationHandler.activeChatPubkey;
  static set activeChatPubkey(String? value) {
    chat_notif.ChatNotificationHandler.activeChatPubkey = value;
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
      AndroidInitializationSettings('@drawable/ic_stat_chatme');
      const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
      );

      // Cold start: app was launched by tapping Answer on a call notification.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final launchResponse = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true &&
          launchResponse?.actionId == CallNotificationHandler.answerActionId) {
        debugPrint('[Notification] Launched by Answer tap');
        _onNotificationResponse(launchResponse!);
      }

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
        FirebaseMessaging.onMessage.listen((message) {
          chat_notif.ChatNotificationHandler.handleForegroundMessage(message, _plugin);
        }),
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

  /// Show a chat notification with MessagingStyle stacking.
  static Future<void> showChatNotification({
    required String senderPubkey,
    required String senderName,
    required String message,
    bool showActions = true,
  }) async {
    if (kIsWeb) return;
    await chat_notif.ChatNotificationHandler.showChatNotification(
      senderPubkey: senderPubkey,
      senderName: senderName,
      message: message,
      showActions: showActions,
      pluginInstance: _plugin,
    );
    await chat_notif.ChatNotificationHandler.showSummaryIfNeeded(_plugin);
  }

  /// Dismiss notification for a specific contact.
  static Future<void> clearNotification(String senderPubkey) async {
    await chat_notif.ChatNotificationHandler.clearNotification(senderPubkey, _plugin);
  }

  /// Dismiss all chat notifications.
  static Future<void> clearAllNotifications() async {
    await chat_notif.ChatNotificationHandler.clearAllNotifications(_plugin);
  }

  /// Incoming call heads-up with Answer / Decline.
  static Future<void> showIncomingCall({
    required String callerPubkey,
    required String callerName,
  }) async {
    if (kIsWeb) return;
    await CallNotificationHandler.showIncomingCall(
      plugin: _plugin,
      callerPubkey: callerPubkey,
      callerName: callerName,
    );
  }

  static Future<void> cancelIncomingCall() async {
    if (kIsWeb) return;
    await CallNotificationHandler.cancelIncomingCall(_plugin);
  }

  /// Simple notification for calls / non-chat events.
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await CallNotificationHandler.showNotification(
      id: id,
      title: title,
      body: body,
      payload: payload,
      plugin: _plugin,
      channelId: _channelId,
      channelName: _channelName,
      channelDescription: _channelDescription,
    );
  }
}
