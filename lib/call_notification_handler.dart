// call_notification_handler.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CallNotificationHandler {
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
      icon: '@mipmap/ic_launcher',
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
}
