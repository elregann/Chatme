// notification_handler.dart

import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer, DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'call_notification_handler.dart';
import 'chat_manager.dart';
import 'chat_notification_handler.dart' as chat_notif;
import 'core/utils/background_call_signal.dart';
import 'core/utils/background_chat_actions.dart';
import 'core/utils/bg_inbox.dart';

/// Entry point for FCM messages received while the app is in background or
/// closed. The real work lives in chat_notification_handler.dart.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  return await chat_notif.firebaseMessagingBackgroundHandler(message);
}

/// Entry point for notification action buttons (Answer, Decline, Reply,
/// Mark as Read) tapped while the app is in background or closed.
///
/// The app (main isolate) may or may not be alive:
///  - If it is alive, the tap is forwarded to it so it can update its UI.
///  - Actions that must not depend on the app are also done here directly,
///    with a fresh relay connection.
@pragma('vm:entry-point')
Future<void> backgroundNotificationResponseHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final String? peerPubkey = response.payload;
  final SendPort? sendPort = IsolateNameServer.lookupPortByName('chatme_notification_port');
  final bool appIsAlive = sendPort != null;

  // Let the live app do its own UI cleanup.
  sendPort?.send({
    'actionId': response.actionId,
    'input': response.input,
    'payload': response.payload,
  });

  if (peerPubkey == null || peerPubkey.isEmpty) return;

  if (response.actionId == CallNotificationHandler.declineActionId) {
    // App is not running: leave a note so it saves the call record when opened.
    if (!appIsAlive) {
      await BgInbox.recordDeclinedCall(peerPubkey);
    }
    // Always tell the caller directly: relying on the app's own connection
    // fails when the app is only paused in the background.
    await BackgroundCallSignal.sendHangup(peerPubkey);
  } else if (response.actionId == chat_notif.ChatNotificationHandler.markReadActionId) {
    // The app only knows messages already saved in Hive. Messages that arrived
    // through FCM are not there yet, so their receipts are sent from here too.
    await BackgroundChatActions.markRead(peerPubkey);
  } else if (response.actionId == chat_notif.ChatNotificationHandler.replyActionId) {
    // When the app is alive it handles the reply itself (through the port).
    final String? replyText = response.input;
    if (!appIsAlive && replyText != null && replyText.isNotEmpty) {
      await BackgroundChatActions.sendReply(peerPubkey, replyText);
    }
  }
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

  // Channel constants (shared with the chat handler)
  static const String _channelId = chat_notif.ChatNotificationHandler.channelId;
  static const String _channelName = chat_notif.ChatNotificationHandler.channelName;
  static const String _channelDescription = chat_notif.ChatNotificationHandler.channelDescription;

  // FCM subscriptions and init state
  static final List<StreamSubscription> _fcmSubscriptions = [];
  static bool _initialized = false;

  /// Pubkey of the chat room currently open.
  static String? get activeChatPubkey => chat_notif.ChatNotificationHandler.activeChatPubkey;
  static set activeChatPubkey(String? value) {
    chat_notif.ChatNotificationHandler.activeChatPubkey = value;
  }

  /// Initializes notifications and FCM. Safe to call multiple times.
  static Future<void> init({dynamic relayManager}) async {
    if (kIsWeb) return;
    if (_initialized) return;

    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Permissions
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Local notification plugin
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@drawable/ic_stat_chatme');
      const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: backgroundNotificationResponseHandler,
      );

      // Cold start: the app was launched by tapping Answer on a call notification.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final launchResponse = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true &&
          launchResponse?.actionId == CallNotificationHandler.answerActionId) {
        _onNotificationResponse(launchResponse!);
      }

      // Cold start: the app was opened by tapping a chat or "Missed Call"
      // notification. The ringing call notification is excluded.
      if (launch?.didNotificationLaunchApp == true &&
          launchResponse != null &&
          (launchResponse.actionId == null || launchResponse.actionId!.isEmpty) &&
          launchResponse.id != CallNotificationHandler.incomingCallNotificationId) {
        final String? tappedPeer = launchResponse.payload;
        if (tappedPeer != null && tappedPeer.isNotEmpty) {
          onNotificationClick.add(tappedPeer);
        }
      }

      // Chat notification channel
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

      // Foreground FCM: show as a local notification
      _fcmSubscriptions.add(
        FirebaseMessaging.onMessage.listen((message) {
          chat_notif.ChatNotificationHandler.handleForegroundMessage(message, _plugin);
        }),
      );

      // App resumed from background by tapping a notification
      _fcmSubscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          final senderPubkey = message.data['senderPubkey'] ?? '';
          if (senderPubkey.isNotEmpty) onNotificationClick.add(senderPubkey);
        }),
      );

      // App launched from a killed state by tapping a notification
      final RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final senderPubkey = initialMessage.data['senderPubkey'] ?? '';
        if (senderPubkey.isNotEmpty) onNotificationClick.add(senderPubkey);
      }

      // Inline reply (app alive)
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

      _initialized = true;
    } catch (e) {
      debugPrint('[Notification] Init failed | $e');
    }
  }

  /// Notification tap or action button pressed while the app is alive.
  /// Forwards the event to the main isolate through its named port.
  @pragma('vm:entry-point')
  static void _onNotificationResponse(NotificationResponse response) {
    final SendPort? sendPort = IsolateNameServer.lookupPortByName('chatme_notification_port');
    sendPort?.send({
      'actionId': response.actionId,
      'input': response.input,
      'payload': response.payload,
    });
  }

  /// Shows a chat notification with MessagingStyle stacking.
  static Future<void> showChatNotification({
    required String senderPubkey,
    required String senderName,
    required String message,
    bool showActions = true,
    bool replyOnly = false,
  }) async {
    if (kIsWeb) return;
    await chat_notif.ChatNotificationHandler.showChatNotification(
      senderPubkey: senderPubkey,
      senderName: senderName,
      message: message,
      showActions: showActions,
      replyOnly: replyOnly,
      pluginInstance: _plugin,
    );
    await chat_notif.ChatNotificationHandler.showSummaryIfNeeded(_plugin);
  }

  /// Dismisses the notification of a specific contact.
  static Future<void> clearNotification(String senderPubkey) async {
    await chat_notif.ChatNotificationHandler.clearNotification(senderPubkey, _plugin);
  }

  /// Dismisses all chat notifications.
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
