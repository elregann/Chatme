// call_notification_handler.dart

import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/theme/chatme_colors.dart';
import 'core/utils/notification_profile.dart';
import 'core/utils/ongoing_call_style_channel.dart';
import 'core/utils/ongoing_call_style_payload.dart';
import 'core/utils/shortcut_helper.dart';

class CallNotificationHandler {
  static const String callChannelId = 'chatme_incoming_call_channel_v2';
  static const String callChannelName = 'Incoming Calls';
  static const String answerActionId = 'ANSWER_CALL_ACTION';
  static const String declineActionId = 'DECLINE_CALL_ACTION';
  static const int incomingCallNotificationId = 888888;
  static const int activeCallNotificationId = 888889;
  static const String activeCallChannelId = 'chatme_active_call_channel';
  static const String endCallActionId = 'END_CALL_ACTION';

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
      icon: '@drawable/ic_stat_call',
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
    String? nameHint,
  }) async {
    const AndroidNotificationAction answerAction = AndroidNotificationAction(
      answerActionId,
      'Answer',
      showsUserInterface: true,
      cancelNotification: true,
      titleColor: ChatmeColors.callAccept,
    );

    const AndroidNotificationAction declineAction = AndroidNotificationAction(
      declineActionId,
      'Decline',
      showsUserInterface: false,
      cancelNotification: true,
      titleColor: ChatmeColors.callEnd,
    );

    // Resolve local display name and avatar (same logic as chat notifications)
    String displayName = callerName;
    Uint8List? avatarBytes;
    try {
      final profile =
          await NotificationProfile.resolve(callerPubkey, nameHint: nameHint);
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
      timeoutAfter: 60000,
      icon: '@drawable/ic_stat_call',
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
      color: ChatmeColors.notificationAccent,
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

  static int _ongoingSeq = 0;

  // Last shortcut written by the ongoing-call path. The avatar bytes are
  // cached by NotificationProfile, so identity comparison is enough to skip
  // redundant platform-channel round-trips on connecting → active changes.
  static String? _lastShortcutId;
  static String? _lastShortcutName;
  static Uint8List? _lastShortcutAvatar;

  static Future<void> startOngoingCall({
    required FlutterLocalNotificationsPlugin plugin,
    required String peerName,
    required String peerPubkey,
    required int startedAtMs,
    String? status,
  }) async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    final seq = ++_ongoingSeq;
    final showTimer = status == null;
    final statusText = status ?? 'Ongoing voice call';

    String displayName = peerName;
    Uint8List? avatarBytes;
    if (peerPubkey.isNotEmpty) {
      try {
        final profile = await NotificationProfile.resolve(peerPubkey);
        // Keep the exact name shown on the call screen. The profile name is
        // only a fallback when the session did not provide one.
        displayName = OngoingCallStylePayload.displayName(
          sessionName: peerName,
          fallbackName: profile.name,
        );
        avatarBytes = profile.avatarPng;
      } catch (e) {
        debugPrint('[Notification] Ongoing call profile failed | $e');
      }
      try {
        final shortcutChanged = _lastShortcutId != peerPubkey ||
            _lastShortcutName != displayName ||
            !identical(_lastShortcutAvatar, avatarBytes);
        if (shortcutChanged) {
          await ShortcutHelper.pushConversationShortcut(
            id: peerPubkey,
            name: displayName,
            avatarBytes: avatarBytes,
          );
          _lastShortcutId = peerPubkey;
          _lastShortcutName = displayName;
          _lastShortcutAvatar = avatarBytes;
        }
      } catch (e) {
        debugPrint('[Notification] Ongoing call shortcut failed | $e');
      }
    }

    if (seq != _ongoingSeq) return;

    final details = AndroidNotificationDetails(
      activeCallChannelId,
      'Active Calls',
      channelDescription: 'Ongoing voice call',
      importance: Importance.low,
      priority: Priority.low,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: showTimer,
      when: showTimer ? startedAtMs : null,
      usesChronometer: showTimer,
      icon: '@drawable/ic_stat_call',
      color: ChatmeColors.notificationAccent,
      shortcutId: peerPubkey.isEmpty ? null : 'chat_shortcut_$peerPubkey',
      styleInformation: MessagingStyleInformation(
        const Person(name: 'You', key: 'me'),
        groupConversation: false,
        messages: [
          Message(
            statusText,
            DateTime.now(),
            Person(
              name: displayName,
              key: peerPubkey,
              important: true,
              icon: avatarBytes != null ? ByteArrayAndroidIcon(avatarBytes) : null,
            ),
          ),
        ],
      ),
      actions: const [
        AndroidNotificationAction(
          endCallActionId,
          'Hang Up',
          showsUserInterface: false,
          cancelNotification: false,
          titleColor: ChatmeColors.callEnd,
        ),
      ],
    );

    var foregroundStarted = false;
    try {
      await android.startForegroundService(
        activeCallNotificationId,
        displayName,
        statusText,
        notificationDetails: details,
        payload: peerPubkey,
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeMicrophone,
        },
      );
      foregroundStarted = true;
    } catch (e) {
      debugPrint('[Notification] Ongoing call start failed | $e');
    }
    if (!foregroundStarted || seq != _ongoingSeq) return;

    // On Android 12+ the platform call chip is driven by Notification.CallStyle.
    // Restyle only the connected call; every other state keeps the plugin's
    // notification exactly as before.
    final callStyle = OngoingCallStylePayload.forActiveCall(
      channelId: activeCallChannelId,
      notificationId: activeCallNotificationId,
      endActionId: endCallActionId,
      accentArgb: ChatmeColors.notificationAccent.toARGB32(),
      status: status,
      title: displayName,
      peerPubkey: peerPubkey,
      startedAtMs: startedAtMs,
      avatar: avatarBytes,
    );
    if (callStyle == null) return;

    await OngoingCallStyleChannel.apply(callStyle);
    if (seq != _ongoingSeq) {
      await OngoingCallStyleChannel.clear(
        notificationId: activeCallNotificationId,
      );
    }
  }

  static Future<void> stopOngoingCall(FlutterLocalNotificationsPlugin plugin) async {
    final seq = ++_ongoingSeq;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.stopForegroundService();
    } catch (e) {
      debugPrint('[Notification] Ongoing call stop failed | $e');
    }
    if (seq != _ongoingSeq || android == null) return;

    // The shim posts with the same id as the foreground notification, so make
    // sure a stopped call never leaves a stale chip behind.
    await OngoingCallStyleChannel.clear(
      notificationId: activeCallNotificationId,
    );
  }
}