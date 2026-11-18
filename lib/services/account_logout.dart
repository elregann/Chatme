// account_logout.dart
//
// Signs the user out of the local account. Everything stored on this device is
// wiped and AppSettings.load() generates a brand-new keypair, exactly like a
// fresh install. The old account itself is untouched: no directory release and
// no profile broadcast, so its profile stays intact when restored elsewhere.

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive/hive.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../call_manager.dart';
import '../core/utils/bg_inbox.dart';
import '../core/utils/shortcut_helper.dart';
import '../core/utils/sync_gate.dart';
import '../models/call_log.dart';
import '../models/chat_message.dart';
import '../models/contact.dart';
import '../notification_handler.dart';
import '../relay_manager.dart';
import '../services/chat_reply.dart';
import 'app_settings.dart';
import 'link_preview_service.dart';
import 'media_storage.dart';
import 'profile_meta_store.dart';
import 'voice_storage.dart';

class AccountLogout {
  AccountLogout._();

  /// Test seam: production wipes the in-app browser's cookies and site data,
  /// tests only record that the step ran (no native WebView in widget tests).
  static Future<void> Function() clearWebViewData = _clearWebViewData;

  /// Wipes local state, creates the new account, and reconnects in place.
  static Future<void> signOut(RelayManager relayManager) async {
    final oldPubkey = AppSettings.instance.myPubkey;

    // Stop live traffic before deleting the state it writes to.
    await _guard('relay disconnect', () async => relayManager.disconnect());
    ChatScreenRegistry.clearAll();
    await _guard('reset call state', _resetCallState);
    await _guard(
      'FCM unsubscribe',
      () => _unsubscribe(oldPubkey),
    );

    // Notification bar, file mailbox and launcher shortcuts.
    await _guard('stop call notification', NotificationHandler.stopOngoingCall);
    await _guard(
      'clear notifications',
      NotificationHandler.clearAllNotifications,
    );
    await _guard('clear mailbox', BgInbox.clearAll);
    await _guard('clear media', () => _clearFolder(mediaDirectory));
    await _guard('clear voice notes', () => _clearFolder(voiceDirectory));
    await _guard('clear shortcuts', ShortcutHelper.removeConversationShortcuts);

    // Hive data and caches. The gate is ended first because its flags live in
    // the settings box that is about to be cleared.
    SyncGate.finish('logout');
    await _wipeLocalData();

    // Empty my_pubkey makes load() generate a keypair and start a fresh sync
    // gate — the same path as the very first launch.
    await AppSettings.instance.load();

    final newPubkey = AppSettings.instance.myPubkey;
    await _guard('FCM subscribe', () => _subscribe(newPubkey));
    await _guard('relay connect', () async => relayManager.connect());
  }

  /// Downloads and voice notes live in their own folders outside Hive.
  static Future<void> _clearFolder(Future<Directory> Function() directory) async {
    final dir = await directory();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  static Future<void> _resetCallState() async {
    final call = CallManager.instance;
    call.pendingIncoming = null;
    call.autoAnswerPubkey = null;
    call.launchCallerPubkey = null;
    call.launchAutoAccept = false;
  }

  static Future<void> _unsubscribe(String pubkey) async {
    if (kIsWeb || pubkey.isEmpty) return;
    await FirebaseMessaging.instance
        .unsubscribeFromTopic(pubkey)
        .timeout(const Duration(seconds: 8));
  }

  static Future<void> _subscribe(String pubkey) async {
    if (kIsWeb || pubkey.isEmpty) return;
    await FirebaseMessaging.instance
        .subscribeToTopic(pubkey)
        .timeout(const Duration(seconds: 8));
  }

  static Future<void> _wipeLocalData() async {
    // Hive boxes opened with a type must be fetched with that same type.
    await _guard('clear contacts', () async {
      if (Hive.isBoxOpen('contacts')) await Hive.box<Contact>('contacts').clear();
    });
    await _guard('clear chats', () async {
      if (Hive.isBoxOpen('chats')) await Hive.box('chats').clear();
    });
    await _guard('clear chat_msgs', () async {
      if (Hive.isBoxOpen('chat_msgs')) {
        await Hive.box<ChatMessage>('chat_msgs').clear();
      }
    });
    await _guard('clear profile_pictures', () async {
      if (Hive.isBoxOpen('profile_pictures')) {
        await Hive.box<String>('profile_pictures').clear();
      }
    });
    await _guard('clear call_logs', () async {
      if (Hive.isBoxOpen('call_logs')) {
        await Hive.box<CallLog>('call_logs').clear();
      }
    });
    await _guard('clear processed_events', () async {
      if (Hive.isBoxOpen('processed_events')) {
        await Hive.box('processed_events').clear();
      }
    });
    await _guard('clear profile cache', ProfileMetaStore.clearAll);
    await _guard('clear link previews', LinkPreviewService.instance.clear);
    await _guard('clear WebView data', clearWebViewData);
    await _guard('clear settings', () async {
      if (Hive.isBoxOpen('settings')) await Hive.box('settings').clear();
    });
  }

  /// Discovery web apps live in a shared WebView data store. A logout must not
  /// leave their cookies, local storage or caches behind for the new account.
  /// A temporary controller is enough: WebView.clearCache is app-wide, and
  /// the cookie manager is global to every WebView in the app.
  static Future<void> _clearWebViewData() async {
    await WebViewCookieManager().clearCookies();
    final controller = WebViewController();
    await controller.clearCache();
    await controller.clearLocalStorage();
  }

  static Future<void> _guard(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      debugPrint('[Logout] $label failed | $e');
    }
  }
}
