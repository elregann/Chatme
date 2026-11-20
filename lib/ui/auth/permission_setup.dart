// permission_setup.dart
//
// Explains each Android system window before opening it. Actual permission
// status is read from the platform, so already-granted access never prompts
// again and "Not now" can be retried on the next launch.

import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/chatme_colors.dart';
import '../../notification_handler.dart';

class PermissionSetup {
  PermissionSetup._();

  static bool _showing = false;

  /// Shows each explanation once the UI is visible and an account exists.
  /// Declining is not persisted: the next launch offers the request again.
  static Future<void> maybeShow(BuildContext context) async {
    if (kIsWeb || _showing || !context.mounted) return;
    _showing = true;
    try {
      final notificationsGranted = await _notificationsGranted();
      final batteryExempt = await _batteryExempt();
      if (!context.mounted) return;
      if (notificationsGranted && batteryExempt) return;

      if (!notificationsGranted) {
        final allowNotifications = await _explain(
          context,
          title: 'Stay reachable',
          message:
              'Chatme will ask to show notifications. This lets new messages and incoming calls alert you while the app is in the background.',
          confirmLabel: 'Continue',
        );
        if (!context.mounted || !allowNotifications) return;
        await NotificationHandler.requestPermissions();
      }

      if (Platform.isAndroid && !batteryExempt && context.mounted) {
        final openBatterySetting = await _explain(
          context,
          title: 'Keep calls ringing',
          message:
              'Android will open a system screen asking whether Chatme can ignore battery optimizations. Allowing it keeps incoming calls ringing in the background.',
          confirmLabel: 'Open system setting',
        );
        if (openBatterySetting) {
          try {
            await const MethodChannel('com.chatme.app/battery')
                .invokeMethod('requestIgnoreBatteryOptimization');
          } catch (e) {
            debugPrint('[Permissions] Battery setting failed | $e');
          }
        }
      }
    } finally {
      _showing = false;
    }
  }

  static Future<bool> _notificationsGranted() async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _batteryExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      return await const MethodChannel('com.chatme.app/battery')
              .invokeMethod<bool>('isIgnoringBatteryOptimization') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _explain(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ChatmeColors.surfaceRaised,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: ChatmeColors.textPrimary,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: ChatmeColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Not now',
              style: TextStyle(color: ChatmeColors.textMuted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: ChatmeColors.buttonPrimary,
              foregroundColor: ChatmeColors.buttonOnPrimary,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
