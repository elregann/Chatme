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
import 'core/utils/notification_profile.dart';
import 'models/contact.dart';
import 'core/utils/shortcut_helper.dart';
import 'call_notification_handler.dart';
import 'core/utils/bg_inbox.dart';

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

  // Incoming call: ring and show Answer / Decline, skip chat handling.
  if (message.data['type'] == 'call') {
    final callPlugin = FlutterLocalNotificationsPlugin();
    await callPlugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_chatme'),
    ));
    await CallNotificationHandler.showIncomingCall(
      plugin: callPlugin,
      callerPubkey: senderPubkey,
      callerName: senderName,
    );
    return;
  }

  // Caller hung up or timed out: dismiss the ringing notification.
  if (message.data['type'] == 'call_cancel') {
    final cancelPlugin = FlutterLocalNotificationsPlugin();
    await cancelPlugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_chatme'),
    ));
    await cancelPlugin.cancel(CallNotificationHandler.incomingCallNotificationId);

    // Leave a note: the app saves the missed call (and shows its notification)
    // the next time it opens. This isolate never writes to Hive.
    await BgInbox.recordMissedCall(senderPubkey);

    // Show "Missed Call" like a chat notification (same style, avatar and name).
    await ChatNotificationHandler.showChatNotification(
      senderPubkey: senderPubkey,
      senderName: senderName,
      message: 'Missed Call',
      showActions: false,
      pluginInstance: cancelPlugin,
    );
    return;
  }

  final settingsBox = await Hive.openBox('settings');
  final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
  final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;

  String plaintext = 'You have a new message';
  String rumorId = '';
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
        rumorId = nip17Result.rumorId;
      } else {
        final decrypted = Nip04.decrypt(ciphertext, myPrivkey, senderPubkey);
        if (decrypted.isNotEmpty) plaintext = decrypted;
      }
    } catch (e) {
      debugPrint('[BgFcm] decode failed | $e');
    }
  }

  // Mark as notified so the foreground handler does not duplicate
  await settingsBox.put('notified_$eventId', true);

  if (rumorId.isNotEmpty) {
    try {
      await BgInbox.addUnread(senderPubkey, rumorId);
    } catch (e) {
      debugPrint('[BgFcm] record failed | $e');
    }
  }

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('@drawable/ic_stat_chatme'),
  ));

  await ChatNotificationHandler.showChatNotification(
    senderPubkey: senderPubkey,
    senderName: senderName,
    message: plaintext,
    showActions: true,
    pluginInstance: plugin,
  );
}

class ChatNotificationHandler {
  // In-memory message history per contact (for MessagingStyle stacking)
  static final Map<String, List<Map<String, String>>> _messageHistory = {};

  // Channel & action constants
  static const String channelId = 'chat_me_urgent_channel_v2';
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
  /// Name + avatar are resolved with the same rules as the in-app UI.
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

    final profile = await NotificationProfile.resolve(senderPubkey);
    final String displayName = profile.name;
    final ByteArrayAndroidIcon? avatarIcon = profile.avatarPng != null
        ? ByteArrayAndroidIcon(profile.avatarPng!)
        : null;

    // Fix Stale Message Bug: Check if unreadCount for this contact is 0 or box doesn't have unread history,
    // if so, clear stale history so old read messages don't reappear alongside new ones.
    try {
      if (Hive.isBoxOpen('contacts')) {
        final contactsBox = Hive.box<Contact>('contacts');
        final contact = contactsBox.get(senderPubkey);
        if (contact != null && contact.unreadCount <= 1) {
          _messageHistory.remove(senderPubkey);
        }
      }
    } catch (_) {}

    // Append to history for this contact
    final history = _messageHistory.putIfAbsent(senderPubkey, () => []);
    history.add({
      'sender': displayName,
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
      Person(
        name: m['sender']!,
        key: senderPubkey,
        important: false,
        icon: avatarIcon,
      ),
    ))
        .toList();

    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
      const Person(name: 'You', key: 'me'),
      groupConversation: false,
      messages: styleMessages,
    );

    await ShortcutHelper.pushConversationShortcut(
      id: senderPubkey,
      name: displayName,
      avatarBytes: profile.avatarPng,
    );

    // Action: inline reply
    const AndroidNotificationAction replyAction = AndroidNotificationAction(
      replyActionId,
      'Reply',
      inputs: [AndroidNotificationActionInput(label: 'Message')],
      showsUserInterface: false,
      cancelNotification: false,
    );

    // Action: mark as read
    const AndroidNotificationAction markReadAction = AndroidNotificationAction(
      markReadActionId,
      'Mark as Read',
      showsUserInterface: false,
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
      icon: '@drawable/ic_stat_chatme',
      color: const Color(0xFF2196F3),
      shortcutId: 'chat_shortcut_$senderPubkey',
      autoCancel: true,
      ongoing: false,
      onlyAlertOnce: false,
    );

    final NotificationDetails details = NotificationDetails(android: androidDetails);
    final int notifId = notificationId(senderPubkey);

    if (pluginInstance != null) {
      try {
        await pluginInstance.show(notifId, displayName, message, details, payload: senderPubkey);
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
      icon: '@drawable/ic_stat_chatme',
      color: Color(0xFF2196F3),
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
