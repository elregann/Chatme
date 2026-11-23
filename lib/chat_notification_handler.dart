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
import 'core/crypto/nip17_file.dart';
import 'core/crypto/nip04.dart';
import 'core/theme/chatme_colors.dart';
import 'core/utils/notification_entry.dart';
import 'core/utils/notification_profile.dart';
import 'core/utils/notification_summary.dart';
import 'core/utils/sync_gate.dart';
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
      nameHint: ChatNotificationHandler.pushNameHint(message.data),
      avatarHint: ChatNotificationHandler.pushAvatarHint(message.data),
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

    // Leave a note: the app saves the missed call the next
    // time it opens. This isolate never writes to Hive.
    await BgInbox.recordMissedCall(senderPubkey);

    // Show "Missed Call" like a chat notification (same style, avatar and name).
    await ChatNotificationHandler.showChatNotification(
      senderPubkey: senderPubkey,
      senderName: senderName,
      message: 'Missed Call',
      showActions: true,
      replyOnly: true,
      messageId: eventId,
      pluginInstance: cancelPlugin,
      nameHint: ChatNotificationHandler.pushNameHint(message.data),
      avatarHint: ChatNotificationHandler.pushAvatarHint(message.data),
    );
    return;
  }

  // Leave the raw gift wrap for the main isolate. It re-verifies and persists
  // the message when the app is opened; this isolate only needs the preview.
  if (ephemeralPubkey.isNotEmpty && ciphertext.isNotEmpty) {
    try {
      await BgInbox.writePendingMessage(
        eventId: eventId,
        ephemeralPubkey: ephemeralPubkey,
        ciphertext: ciphertext,
      );
    } catch (e) {
      debugPrint('[BgFcm] spool failed | $e');
    }
  }

  final settingsBox = await Hive.openBox('settings');
  final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
  final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;

  String plaintext = 'You have a new message';
  String rumorId = '';
  // The FCM payload's senderPubkey is untrusted. Prefer the one authenticated
  // by the Seal, so background read markers match the saved message's peer.
  String verifiedSenderPubkey = senderPubkey;
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
        verifiedSenderPubkey = nip17Result.senderPubkey;
        if (nip17Result.rumorKind == Nip17.kindFile) {
          final file = FileMessage.parse(
            content: nip17Result.plaintext,
            tags: nip17Result.rumorTags,
          );
          if (file == null) return;
          plaintext = file.previewLabel;
        } else if (nip17Result.rumorKind != Nip17.kindRumor) {
          return;
        } else if (nip17Result.plaintext.isNotEmpty) {
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
      await BgInbox.addUnread(verifiedSenderPubkey, rumorId);
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
    messageId: ChatNotificationHandler.notificationMessageId(
      rumorId: rumorId,
      eventId: eventId,
    ),
    pluginInstance: plugin,
    nameHint: ChatNotificationHandler.pushNameHint(message.data),
    avatarHint: ChatNotificationHandler.pushAvatarHint(message.data),
  );
}

class ChatNotificationHandler {
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
  static Future<void> handleForegroundMessage(
    RemoteMessage message,
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    final senderPubkey = message.data['senderPubkey'] ?? '';
    final senderName = message.data['senderName'] ?? 'New Message';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final eventId = message.data['eventId'] ?? '';
    final ciphertext = message.data['ciphertext'] ?? '';
    final ephemeralPubkey = message.data['ephemeralPubkey'] ?? '';
    final fcmType = message.data['type'] ?? '';

    // During the initial sync (account restore / first login) the relays
    // are replaying stored history — stay silent. Incoming calls are the
    // exception: they are live, time-sensitive signals, never history.
    if (SyncGate.isActive && fcmType != 'call' && fcmType != 'call_cancel') {
      return;
    }

    // The ringing notification and the relay signal own the live call path.
    if (fcmType == 'call') return;

    if (eventId.isNotEmpty) {
      try {
        if (Hive.box('settings').get('notified_$eventId') == true) {
          return;
        }
      } catch (_) {}
    }

    // The background isolate records this note, but it is not invoked while
    // the app is foregrounded. Keep the same fallback here so the room bubble
    // can still be rebuilt if the relay hangup signal is missed.
    if (fcmType == 'call_cancel') {
      // A hangup is handled right here, so it still owns the dedup flag.
      if (eventId.isNotEmpty) {
        try {
          await Hive.box('settings').put('notified_$eventId', true);
        } catch (_) {}
      }
      try {
        await plugin.cancel(CallNotificationHandler.incomingCallNotificationId);
      } catch (_) {}
      if (senderPubkey.isNotEmpty) {
        await BgInbox.recordMissedCall(senderPubkey);
      }
      return;
    }

    // The FCM event id is a fresh Gift Wrap id on every retry; the Rumor id
    // inside it is what identifies the message for the notification stack.
    String rumorId = '';
    if (ephemeralPubkey.isNotEmpty && ciphertext.isNotEmpty) {
      try {
        final settingsBox = Hive.box('settings');
        final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
        final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;
        if (myPrivkey.isNotEmpty) {
          final result = await Nip17.unwrap(
            giftWrapEvent: {
              'pubkey': ephemeralPubkey,
              'content': ciphertext,
              'kind': 1059,
            },
            receiverPrivkey: myPrivkey,
            receiverPubkey: myPubkey,
          );
          rumorId = result.rumorId;
        }
      } catch (_) {}
    }

    if (senderPubkey.isNotEmpty && body.isNotEmpty) {
      // Claim the event only when a notification is really attempted. The
      // worker sends data-only pushes, so this path shows nothing and the
      // relay delivery must stay free to notify the user.
      if (eventId.isNotEmpty) {
        try {
          await Hive.box('settings').put('notified_$eventId', true);
        } catch (_) {}
      }

      await showChatNotification(
        senderPubkey: senderPubkey,
        senderName: senderName,
        message: body,
        messageId: notificationMessageId(
          rumorId: rumorId,
          eventId: eventId,
        ),
        pluginInstance: plugin,
        nameHint: pushNameHint(message.data),
        avatarHint: pushAvatarHint(message.data),
      );
    }
  }

  /// The sender's own name from a push, or null when it carries none. A
  /// legacy cancel push using the fixed "ChatMe" label never hints.
  static String? pushNameHint(Map<String, dynamic> data) {
    final name = data['senderName'];
    if (name is! String || name.trim().isEmpty) return null;
    final trimmed = name.trim();
    if (trimmed.toLowerCase() == 'chatme') return null;
    return trimmed;
  }

  /// The sender's avatar URL carried by a push, or null when absent or malformed.
  static String? pushAvatarHint(Map<String, dynamic> data) {
    final avatar = data['senderAvatar'];
    if (avatar is! String || avatar.trim().isEmpty) return null;
    return NotificationProfile.cleanAvatarHint(avatar);
  }

  /// Stable notification ID derived from pubkey (survives app restarts).
  static int notificationId(String pubkey) {
    final digest = sha256.convert(utf8.encode(pubkey)).bytes;
    return ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]).abs() % 1000000;
  }

  /// One message keeps one stack entry even when a retry gets a new wrap id.
  static String notificationMessageId({
    required String rumorId,
    required String eventId,
  }) =>
      rumorId.isNotEmpty ? rumorId : eventId;

  /// Show a chat notification with MessagingStyle stacking. The stack holds
  /// every unread message of the contact until the chat is read or replied
  /// to, [messageId] being what tells one message from another.
  /// Name + avatar are resolved with the same rules as the in-app UI.
  static Future<void> showChatNotification({
    required String senderPubkey,
    required String senderName,
    required String message,
    required String messageId,
    bool showActions = true,
    bool replyOnly = false,
    FlutterLocalNotificationsPlugin? pluginInstance,
    String? nameHint,
    String? avatarHint,
  }) async {
    if (shouldSuppressNotification(senderPubkey)) {
      return;
    }

    final profile = await NotificationProfile.resolve(
      senderPubkey,
      nameHint: nameHint,
      avatarHint: avatarHint,
    );
    final String displayName = profile.name;
    final ByteArrayAndroidIcon? avatarIcon = profile.avatarPng != null
        ? ByteArrayAndroidIcon(profile.avatarPng!)
        : null;

    final int notifId = notificationId(senderPubkey);

    final NotificationEntry entry = NotificationEntry(
      sender: displayName,
      message: message,
      timeMs: DateTime.now().millisecondsSinceEpoch,
    );
    final List<NotificationEntry> stack = await _stackWith(
      senderPubkey,
      messageId.isNotEmpty ? messageId : '${entry.timeMs}',
      entry,
    );

    final List<Message> styleMessages = stack
        .map((item) => Message(
              item.message,
              DateTime.fromMillisecondsSinceEpoch(item.timeMs),
              Person(
                name: item.sender,
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
      actions: showActions
          ? (replyOnly ? [replyAction] : [replyAction, markReadAction])
          : [],
      groupKey: groupKey,
      icon: '@drawable/ic_stat_chatme',
      color: ChatmeColors.notificationAccent,
      shortcutId: 'chat_shortcut_$senderPubkey',
      autoCancel: true,
      ongoing: false,
      onlyAlertOnce: false,
      // The summary must stay quiet; the conversation notifications are the
      // only ones that may alert. This does not change a chat shown alone.
      groupAlertBehavior: GroupAlertBehavior.children,
    );

    final NotificationDetails details = NotificationDetails(android: androidDetails);

    if (pluginInstance != null) {
      try {
        await pluginInstance.show(notifId, displayName, message, details, payload: senderPubkey);
      } catch (e) {
        debugPrint('[Notification] Show failed | $e');
      }

      // Keep the grouped inbox in sync on every path, including the
      // background FCM isolate that never goes through NotificationHandler.
      await showSummaryIfNeeded(pluginInstance);
    }
  }

  /// Adds [entry] to the stack of [senderPubkey] and returns the whole stack.
  /// If the stack cannot be stored, the new message is still shown alone.
  static Future<List<NotificationEntry>> _stackWith(
    String senderPubkey,
    String key,
    NotificationEntry entry,
  ) async {
    try {
      await BgInbox.addToStack(senderPubkey, key, entry);
      return await BgInbox.stackOf(senderPubkey);
    } catch (e) {
      debugPrint('[Notification] Stack unavailable | $e');
      return [entry];
    }
  }

  static Future<void> _clearStack(String senderPubkey) async {
    try {
      await BgInbox.clearStack(senderPubkey);
    } catch (e) {
      debugPrint('[Notification] Stack clear failed | $e');
    }
  }

  /// Show or update the group summary.
  ///
  /// The summary is one inbox for every conversation with unread messages: one
  /// line per conversation, newest first. Android already shows the app name
  /// above it, so the title is the newest line instead of a second "ChatMe".
  /// It is silent and updated in place: the conversation notifications remain
  /// the only ones that alert.
  static Future<void> showSummaryIfNeeded(FlutterLocalNotificationsPlugin plugin) async {
    final List<NotificationEntry> latest;
    try {
      latest = await BgInbox.latestPerConversation();
    } catch (e) {
      debugPrint('[Notification] Summary read failed | $e');
      return;
    }

    // One conversation keeps the plain chat notification, without a wrapper.
    if (latest.length < 2) {
      try {
        await plugin.cancel(summaryNotificationId);
      } catch (e) {
        debugPrint('[Notification] Summary clear failed | $e');
      }
      return;
    }

    final preview = NotificationSummary.previewFor(latest);
    if (preview == null) return;

    final AndroidNotificationDetails summaryDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      groupKey: groupKey,
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(NotificationSummary.linesFor(latest)),
      icon: '@drawable/ic_stat_chatme',
      color: ChatmeColors.notificationAccent,
      autoCancel: true,
      silent: true,
      onlyAlertOnce: true,
      groupAlertBehavior: GroupAlertBehavior.children,
    );

    try {
      await plugin.show(
        summaryNotificationId,
        preview.title,
        preview.body,
        NotificationDetails(android: summaryDetails),
      );
    } catch (e) {
      debugPrint('[Notification] Summary show failed | $e');
    }
  }

  /// Dismiss notification for a specific contact.
  static Future<void> clearNotification(String senderPubkey, FlutterLocalNotificationsPlugin plugin) async {
    final int notifId = notificationId(senderPubkey);
    await plugin.cancel(notifId);
    await _clearStack(senderPubkey);
    await showSummaryIfNeeded(plugin);
  }

  /// Dismiss all chat notifications.
  static Future<void> clearAllNotifications(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.cancelAll();
    try {
      await BgInbox.clearAllStacks();
    } catch (e) {
      debugPrint('[Notification] Stack clear failed | $e');
    }
  }
}
