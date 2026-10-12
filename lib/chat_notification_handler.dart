// chat_notification_handler.dart

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/crypto/nip17.dart';
import 'core/crypto/nip04.dart';

/// Background FCM handler for chat (runs in separate isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await Hive.initFlutter();

  final senderPubkey = message.data['senderPubkey'] ?? '';
  final senderName = message.data['senderName'] ?? 'New Message';
  final ciphertext = message.data['ciphertext'] ?? '';
  final ephemeralPubkey = message.data['ephemeralPubkey'] ?? '';
  final eventId = message.data['eventId'] ?? '';

  if (senderPubkey.isEmpty || eventId.isEmpty) return;

  final settingsBox = await Hive.openBox('settings');
  final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
  final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;

  String plaintext = 'You have a new message';
  if (ciphertext.isNotEmpty && myPrivkey.isNotEmpty) {
    try {
      if (ephemeralPubkey.isNotEmpty) {
        final giftWrapEvent = {
          'pubkey': ephemeralPubkey,
          'content': ciphertext,
          'kind': 1059,
        };
        final nip17Result = await Nip17.unwrap(
          giftWrapEvent: giftWrapEvent,
          receiverPrivkey: myPrivkey,
          receiverPubkey: myPubkey,
        );
        if (nip17Result.plaintext.isNotEmpty) {
          plaintext = nip17Result.plaintext;
        }
      } else {
        final decrypted = Nip04.decrypt(ciphertext, myPrivkey, senderPubkey);
        if (decrypted.isNotEmpty) plaintext = decrypted;
      }
    } catch (_) {}
  }

  // Mark as notified so the foreground handler does not duplicate
  await settingsBox.put('notified_$eventId', true);

  await ChatNotificationHandler.showChatNotification(
    senderPubkey: senderPubkey,
    senderName: senderName,
    message: plaintext,
    showActions: false,
  );
}

class ChatNotificationHandler {
  // In-memory message history per contact (for MessagingStyle stacking)
  static final Map<String, List<Map<String, String>>> _messageHistory = {};

  // Channel & action constants
  static const String channelId = 'chat_me_urgent_channel';
  static const String channelName = 'Messages & Calls';
  static const String channelDescription = 'Notifications for chats and calls';
  static const String replyActionId = 'REPLY_ACTION';
  static const String markReadActionId = 'MARK_READ_ACTION';

  // Notification grouping (all chat notifications share a single group)
  static const String groupKey = 'chatme_chat_group';
  static const int summaryNotificationId = 999999;

  /// Pubkey of the chat room currently open. Used to suppress notifications
  /// for messages from that peer when the app is in foreground.
  static String? activeChatPubkey;

  /// Returns true if a notification from this sender should be suppressed
  /// because the user is already viewing the chat in foreground.
  static bool shouldSuppressNotification(String senderPubkey) {
    if (activeChatPubkey == null) return false;
    if (senderPubkey != activeChatPubkey) return false;
    final state = WidgetsBinding.instance.lifecycleState;
    return state == AppLifecycleState.resumed;
  }

  /// Handle foreground FCM message for chat.
  static void handleForegroundMessage(RemoteMessage message, FlutterLocalNotificationsPlugin plugin) {
    final senderPubkey = message.data['senderPubkey'] ?? '';
    final senderName = message.data['senderName'] ?? 'New Message';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final eventId = message.data['eventId'] ?? '';

    if (eventId.isNotEmpty) {
      try {
        final settingsBox = Hive.box('settings');
        if (settingsBox.get('notified_$eventId') == true) {
          return;
        }
        settingsBox.put('notified_$eventId', true);
      } catch (_) {}
    }

    if (senderPubkey.isNotEmpty && body.isNotEmpty) {
      showChatNotification(
        senderPubkey: senderPubkey,
        senderName: senderName,
        message: body,
        pluginInstance: plugin,
      );
    }
  }

  /// Stable notification ID derived from pubkey (survives app restarts).
  static int notificationId(String pubkey) {
    final digest = sha256.convert(utf8.encode(pubkey)).bytes;
    return ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]).abs() % 1000000;
  }

  /// Show a chat notification with MessagingStyle stacking.
  static Future<void> showChatNotification({
    required String senderPubkey,
    required String senderName,
    required String message,
    bool showActions = true,
    FlutterLocalNotificationsPlugin? pluginInstance,
  }) async {
    if (shouldSuppressNotification(senderPubkey)) {
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
      replyActionId,
      'Reply',
      inputs: [AndroidNotificationActionInput(label: 'Type a message...')],
      showsUserInterface: false,
      cancelNotification: false,
    );

    // Action: mark as read
    const AndroidNotificationAction markReadAction = AndroidNotificationAction(
      markReadActionId,
      'Mark as Read',
      cancelNotification: true,
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      styleInformation: messagingStyle,
      actions: showActions ? [replyAction, markReadAction] : [],
      groupKey: groupKey,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
      ongoing: false,
      onlyAlertOnce: false,
    );

    final NotificationDetails details = NotificationDetails(android: androidDetails);
    final int notifId = notificationId(senderPubkey);

    if (pluginInstance != null) {
      try {
        await pluginInstance.show(notifId, senderName, message, details, payload: senderPubkey);
      } catch (e) {
        debugPrint('[Notification] Show failed | $e');
      }
    }
  }

  /// Show or update the group summary notification.
  static Future<void> showSummaryIfNeeded(FlutterLocalNotificationsPlugin plugin) async {
    final activeCount = _messageHistory.length;
    if (activeCount < 2) return;

    final total = _messageHistory.values.fold<int>(0, (sum, list) => sum + list.length);

    const AndroidNotificationDetails summaryDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      groupKey: groupKey,
      setAsGroupSummary: true,
      icon: '@mipmap/ic_launcher',
      autoCancel: true,
    );

    try {
      await plugin.show(
        summaryNotificationId,
        'ChatMe',
        '$total new messages from $activeCount conversation${activeCount > 1 ? "s" : ""}',
        const NotificationDetails(android: summaryDetails),
      );
    } catch (e) {
      debugPrint('[Notification] Summary show failed | $e');
    }
  }

  /// Dismiss notification for a specific contact.
  static Future<void> clearNotification(String senderPubkey, FlutterLocalNotificationsPlugin plugin) async {
    final int notifId = notificationId(senderPubkey);
    await plugin.cancel(notifId);
    _messageHistory.remove(senderPubkey);

    if (_messageHistory.length < 2) {
      await plugin.cancel(summaryNotificationId);
    } else {
      await showSummaryIfNeeded(plugin);
    }
  }

  /// Dismiss all chat notifications.
  static Future<void> clearAllNotifications(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.cancelAll();
    _messageHistory.clear();
  }
}
