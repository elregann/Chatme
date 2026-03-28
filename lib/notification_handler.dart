// notification_handler.dart

import 'dart:ui';
import 'dart:async';
import 'dart:isolate';
import 'chat_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final senderPubkey = message.data['senderPubkey'] ?? '';
  final senderName = message.data['senderName'] ?? 'Pesan Baru';
  final body = message.data['body'] ?? 'Ada pesan baru masuk!';

  if (senderPubkey.isNotEmpty) {
    await NotificationHandler.showChatNotification(
      senderPubkey: senderPubkey,
      senderName: senderName,
      message: body,
    );
  }
}

@pragma('vm:entry-point')
class NotificationHandler {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Stream untuk navigasi saat notifikasi di-tap
  static final StreamController<String?> onNotificationClick =
  StreamController<String?>.broadcast();

  // Stream untuk inline reply dari notification bar
  static final StreamController<Map<String, String>> onNotificationReply =
  StreamController<Map<String, String>>.broadcast();

  // Cache riwayat pesan per kontak (untuk MessagingStyle stacking)
  // Key: senderPubkey, Value: list of {sender, message}
  static final Map<String, List<Map<String, String>>> _messageHistory = {};

  // Channel & action constants
  static void Function(String senderPubkey, String replyText)? onReplyCallback;
  static const String _channelId = 'chat_me_urgent_channel';
  static const String _channelName = 'Pesan & Panggilan';
  static const String _replyActionId = 'REPLY_ACTION';
  static const String _markReadActionId = 'MARK_READ_ACTION';

  static Future<void> init({dynamic relayManager}) async {
    if (kIsWeb) {
      debugPrint('🌐 Running on Web: Mobile notification initialization skipped.');
      return;
    }

    try {
      await Firebase.initializeApp();
      final FirebaseMessaging messaging = FirebaseMessaging.instance;

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

      // Buat notification channel dengan priority tinggi
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Notifikasi untuk pesan dan panggilan chat',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
      );

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Foreground FCM: tampilkan sebagai notifikasi lokal
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final senderPubkey = message.data['senderPubkey'] ?? '';
        final senderName = message.data['senderName'] ?? 'Pesan Baru';
        final body = message.notification?.body ?? message.data['body'] ?? '';

        if (senderPubkey.isNotEmpty && body.isNotEmpty) {
          showChatNotification(
            senderPubkey: senderPubkey,
            senderName: senderName,
            message: body,
          );
        }
      });

      // App dibuka dari notifikasi (background → foreground)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final senderPubkey = message.data['senderPubkey'] ?? '';
        if (senderPubkey.isNotEmpty) {
          onNotificationClick.add(senderPubkey);
        }
      });

      // App dibuka dari killed state via notifikasi
      final RemoteMessage? initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        final senderPubkey = initialMessage.data['senderPubkey'] ?? '';
        if (senderPubkey.isNotEmpty) {
          onNotificationClick.add(senderPubkey);
        }
      }

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
      debugPrint('🚀 FCM Token: $token');
      debugPrint('✅ NotificationHandler successfully initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize NotificationHandler: $e');
    }
  }

  /// Handler saat notifikasi di-tap atau action button ditekan (foreground)
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

  /// Handler untuk action button di background
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    // Background reply handling — diteruskan saat app aktif kembali
    _onNotificationResponse(response);
  }

  /// Tampilkan notifikasi bergaya chat (MessagingStyle) dengan stacking per kontak
  static Future<void> showChatNotification({
    required String senderPubkey,
    required String senderName,
    required String message,
  }) async {
    // Simpan pesan ke history untuk stacking
    _messageHistory[senderPubkey] ??= [];
    _messageHistory[senderPubkey]!.add({
      'sender': senderName,
      'message': message,
      'time': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    // Batasi history maksimal 10 pesan per kontak
    if (_messageHistory[senderPubkey]!.length > 10) {
      _messageHistory[senderPubkey]!.removeAt(0);
    }

    // Bangun MessagingStyle dari history
    final List<Message> styleMessages = _messageHistory[senderPubkey]!
        .map((m) => Message(
      m['message']!,
      DateTime.fromMillisecondsSinceEpoch(int.parse(m['time']!)),
      Person(
        name: m['sender']!,
        key: senderPubkey,
        important: false,
      ),
    ))
        .toList();

    final MessagingStyleInformation messagingStyle = MessagingStyleInformation(
      const Person(name: 'Saya', key: 'me'),
      conversationTitle: senderName,
      groupConversation: false,
      messages: styleMessages,
    );

    // Action: Reply langsung dari notification bar
    const AndroidNotificationAction replyAction = AndroidNotificationAction(
      _replyActionId,
      'Balas',
      inputs: [
        AndroidNotificationActionInput(
          label: 'Tulis pesan...',
        ),
      ],
      showsUserInterface: false,
      cancelNotification: false,
    );

    // Action: Tandai Dibaca
    const AndroidNotificationAction markReadAction = AndroidNotificationAction(
      _markReadActionId,
      'Tandai Dibaca',
      cancelNotification: true,
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifikasi untuk pesan chat',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.private,
      styleInformation: messagingStyle,
      actions: [replyAction, markReadAction],
      // Grouping: semua pesan dari kontak yang sama masuk ke satu notifikasi
      groupKey: 'chatme_$senderPubkey',
      setAsGroupSummary: false,
      icon: '@mipmap/ic_launcher',
      largeIcon: null,
      autoCancel: true,
      ongoing: false,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    // ID notifikasi konsisten per kontak (bukan random)
    final int notifId = senderPubkey.hashCode.abs() % 2147483647;

    try {
      await _notificationsPlugin.show(
        notifId,
        senderName,
        message,
        notificationDetails,
        payload: senderPubkey, // payload = senderPubkey untuk navigasi
      );
      debugPrint('✅ Notifikasi ditampilkan untuk: $senderName');
    } catch (e) {
      debugPrint('❌ Failed to display notification: $e');
    }
  }

  /// Hapus notifikasi spesifik satu kontak (setelah chat dibuka / mark as read)
  static Future<void> clearNotification(String senderPubkey) async {
    final int notifId = senderPubkey.hashCode.abs() % 2147483647;
    await _notificationsPlugin.cancel(notifId);
    _messageHistory.remove(senderPubkey);
    debugPrint('🧹 Notifikasi dihapus untuk: $senderPubkey');
  }

  /// Hapus semua notifikasi (misal saat user buka app)
  static Future<void> clearAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    _messageHistory.clear();
    debugPrint('🧹 Semua notifikasi dihapus');
  }

  /// Fallback: tampilkan notifikasi sederhana (untuk non-chat, misal panggilan)
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Notifikasi untuk pesan chat',
      importance: Importance.high,
      icon: '@mipmap/ic_launcher',
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      autoCancel: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
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