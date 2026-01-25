import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static final StreamController<String?> onNotificationClick =
  StreamController<String?>.broadcast();

  static Future<void> init() async {
    if (kIsWeb) {
      debugPrint('🌐 Running on Web: Mobile notification initialization skipped.');
      return;
    }

    try {
      await Firebase.initializeApp();
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'chat_me_urgent_channel',
        'Pesan & Panggilan',
        description: 'Notifikasi untuk pesan dan panggilan chat',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          if (response.payload != null) {
            onNotificationClick.add(response.payload);
          }
        },
      );

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          showNotification(
            id: message.hashCode,
            title: message.notification!.title ?? "Pesan Baru",
            body: message.notification!.body ?? "",
            payload: message.data.toString(),
          );
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        onNotificationClick.add(message.data.toString());
      });

      RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        onNotificationClick.add(initialMessage.data.toString());
      }

      String? token = await messaging.getToken();
      debugPrint('🚀 FCM Token: $token');

      debugPrint('✅ NotificationHandler successfully initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize NotificationHandler: $e');
    }
  }

  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    AndroidNotificationDetails androidDetails = const AndroidNotificationDetails(
      'chat_me_urgent_channel',
      'Pesan & Panggilan',
      channelDescription: 'Notifikasi untuk pesan chat',
      importance: Importance.high,
      priority: Priority.high,
      fullScreenIntent: false,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      ticker: 'ticker',
    );

    NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      debugPrint('❌ Failed to display notification: $e');
    }
  }
}