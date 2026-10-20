// call_notification_handler.dart

import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/utils/notification_profile.dart';
import 'core/utils/shortcut_helper.dart';

class CallNotificationHandler {
  static const String callChannelId = 'chatme_incoming_call_channel_v2';
  static const String callChannelName = 'Incoming Calls';
  static const String answerActionId = 'ANSWER_CALL_ACTION';
  static const String declineActionId = 'DECLINE_CALL_ACTION';
  static const int incomingCallNotificationId = 888888;

  /// Simple notification for calls / non-chat events.
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    required FlutterLocalNotificationsPlugin plugin,
    required String channelId,
    required String channelName,
    required String channelDescription,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'chat_me_urgent_channel',
      'Messages & Calls',
      channelDescription: 'Notifications for chats and calls',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      autoCancel: true,
      icon: '@drawable/ic_stat_chatme',
    );

    try {
      await plugin.show(
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

  /// Heads-up notification for an incoming call with Answer / Decline.
  static Future<void> showIncomingCall({
    required FlutterLocalNotificationsPlugin plugin,
    required String callerPubkey,
    required String callerName,
  }) async {
    const AndroidNotificationAction answerAction = AndroidNotificationAction(
      answerActionId,
      'Answer',
      showsUserInterface: true,
      cancelNotification: true,
      titleColor: Color(0xFF2E7D32),
    );

    const AndroidNotificationAction declineAction = AndroidNotificationAction(
      declineActionId,
      'Decline',
      showsUserInterface: false,
      cancelNotification: true,
      titleColor: Color(0xFFC62828),
    );

    // Resolve local display name and avatar (same logic as chat notifications)
    String displayName = callerName;
    Uint8List? avatarBytes;
    try {
      final profile = await NotificationProfile.resolve(callerPubkey);
      displayName = profile.name;
      avatarBytes = profile.avatarPng;
    } catch (e) {
      debugPrint('[Notification] Caller profile failed | $e');
    }

    try {
      await ShortcutHelper.pushConversationShortcut(
        id: callerPubkey,
        name: displayName,
        avatarBytes: avatarBytes,
      );
    } catch (e) {
      debugPrint('[Notification] Caller shortcut failed | $e');
    }

    final AndroidNotificationDetails details = AndroidNotificationDetails(
      callChannelId,
      callChannelName,
      channelDescription: 'Incoming voice calls',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      playSound: true,
      sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      additionalFlags: Int32List.fromList(<int>[4]),
      actions: [declineAction, answerAction],
      autoCancel: false,
      ongoing: true,
      timeoutAfter: 30000,
      icon: '@drawable/ic_stat_chatme',
      shortcutId: 'chat_shortcut_$callerPubkey',
      styleInformation: MessagingStyleInformation(
        const Person(name: 'You', key: 'me'),
        groupConversation: false,
        messages: [
          Message(
            'Incoming voice call',
            DateTime.now(),
            Person(
              name: displayName,
              key: callerPubkey,
              important: true,
              icon: avatarBytes != null ? ByteArrayAndroidIcon(avatarBytes) : null,
            ),
          ),
        ],
      ),
      color: const Color(0xFF2196F3),
    );

    try {
      await plugin.show(
        incomingCallNotificationId,
        displayName,
        'Incoming voice call',
        NotificationDetails(android: details),
        payload: callerPubkey,
      );
    } catch (e) {
      debugPrint('[Notification] Incoming call show failed | $e');
    }
  }

  static Future<void> cancelIncomingCall(FlutterLocalNotificationsPlugin plugin) async {
    await plugin.cancel(incomingCallNotificationId);
  }
}