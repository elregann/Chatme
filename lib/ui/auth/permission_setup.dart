// permission_setup.dart
//
// Explains each Android system window before opening it. The old flow opened
// the battery-optimization setting at cold start with no in-app context, and
// requested the notification permission twice before the UI was visible.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../../core/theme/chatme_colors.dart';
import '../../notification_handler.dart';

class PermissionSetup {
  PermissionSetup._();

  static const String _doneKey = 'permission_setup_done';

  static bool _isDone() {
    try {
      return Hive.box('settings').get(_doneKey, defaultValue: false) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markDone() async {
    try {
      await Hive.box('settings').put(_doneKey, true);
    } catch (_) {}
  }

  /// Shows the explanations once, after the app UI is up and an account
  /// exists. Every system window is preceded by text describing that window.
  static Future<void> maybeShow(BuildContext context) async {
    if (kIsWeb || _isDone() || !context.mounted) return;

    final allowNotifications = await _explain(
      context,
      title: 'Stay reachable',
      message:
          'Chatme will ask to show notifications. This lets new messages and incoming calls alert you while the app is in the background.',
      confirmLabel: 'Continue',
    );
    if (!context.mounted) return;

    if (allowNotifications) {
      await NotificationHandler.requestPermissions();
    } else {
      await _markDone();
      return;
    }

    if (Platform.isAndroid && context.mounted) {
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

    await _markDone();
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
