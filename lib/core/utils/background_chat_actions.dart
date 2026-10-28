// lib/core/utils/background_chat_actions.dart
//
// Chat notification actions (Mark as Read, Reply) that run in the
// notification-action isolate, which can be alive while the main app is closed.
//
// Rules for this isolate:
//  - Hive boxes owned by the main app are opened without compaction, so this
//    isolate never rewrites their files.
//  - Data that other isolates must see goes through BgInbox (one small file per
//    item) instead of a shared Hive box.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../chat_notification_handler.dart';
import '../../models/chat_message.dart';
import '../../models/contact.dart';
import '../crypto/nip17.dart';
import 'bg_inbox.dart';

class BackgroundChatActions {
  /// Relays used for fire-and-forget publishing. messaging.coracle.social is
  /// left out on purpose: it requires NIP-42 AUTH, which is too heavy here.
  static const List<String> _relays = [
    'wss://nos.lol',
    'wss://relay.damus.io',
    'wss://relay.primal.net',
  ];

  // ---------------------------------------------------------------- Mark read

  /// Sends read receipts for the unread messages from [peerPubkey].
  ///
  /// Message ids come from two places:
  ///  - [BgInbox]: messages received via FCM while the app was closed (they are
  ///    not in Hive yet).
  ///  - the `chats` box: messages already saved by the main app (read-only).
  ///
  /// The ids that received a receipt are noted in [BgInbox], so the main app can
  /// mark exactly those messages as read (and clear the badge) when it opens.
  static Future<void> markRead(String peerPubkey) async {
    try {
      await _prepareHive();

      final settingsBox = await _openBox('settings');
      final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
      final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;
      if (myPrivkey.isEmpty || myPubkey.isEmpty) return;

      final idSet = <String>{};
      idSet.addAll(await BgInbox.takeUnread(peerPubkey));

      final chatKey = _chatKey(myPubkey, peerPubkey);
      try {
        final chatsBox = await _openBox('chats');
        final raw = chatsBox.get(chatKey);
        if (raw is List) {
          for (final m in raw.cast<ChatMessage>()) {
            if (m.senderPubkey == peerPubkey &&
                m.status != 'read' &&
                !m.id.startsWith('temp_')) {
              idSet.add(m.id);
            }
          }
        }
      } catch (e) {
        debugPrint('[BgChat] chats box unavailable | $e');
      }

      final ids = idSet.toList();
      if (ids.isEmpty) return;

      // Cap the batch so a long backlog does not flood the relays.
      final toSend = ids.length > 20 ? ids.sublist(ids.length - 20) : ids;
      await BgInbox.recordRead(peerPubkey, toSend);

      final receiptsOn =
          settingsBox.get('read_receipts_enabled', defaultValue: true) == true;
      if (!receiptsOn) return;

      final payloads = <String>[];
      for (final id in toSend) {
        final wrapped = await Nip17.wrap(
          plaintext: 'read',
          senderPrivkey: myPrivkey,
          senderPubkey: myPubkey,
          receiverPubkey: peerPubkey,
          kind: Nip17.kindReadReceipt,
          customTags: [
            ['e', id],
            ['p', peerPubkey],
          ],
        );
        payloads.add(jsonEncode(['EVENT', wrapped.giftWrap]));
      }

      _broadcastToRelays(payloads);
    } catch (e) {
      debugPrint('[BgChat] Mark read failed | $e');
    }
  }

  // -------------------------------------------------------------------- Reply

  /// Sends [replyText] to [peerPubkey] (NIP-17), saves it in the local chat so
  /// it shows up when the app opens, and dismisses the notification.
  static Future<void> sendReply(String peerPubkey, String replyText) async {
    try {
      await _prepareHive();

      final settingsBox = await _openBox('settings');
      final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
      final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;
      if (myPrivkey.isEmpty || myPubkey.isEmpty) return;

      final messageTs = DateTime.now().millisecondsSinceEpoch;
      final chatKey = _chatKey(myPubkey, peerPubkey);

      final wrappedList = await Nip17.wrapMulti(
        plaintext: replyText,
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkeys: [peerPubkey, myPubkey],
        rumorReceiverPubkey: peerPubkey,
        forcedTimestampSec: messageTs ~/ 1000,
      );
      final wrappedRecipient = wrappedList[0];
      final wrappedSelf = wrappedList[1];

      // Save the reply locally so the chat already contains it on next open.
      final chatsBox = await _openBox('chats');
      final raw = chatsBox.get(chatKey);
      final List<ChatMessage> messages =
      (raw is List) ? raw.cast<ChatMessage>().toList() : [];

      messages.add(ChatMessage(
        id: wrappedRecipient.rumorId,
        senderPubkey: myPubkey,
        receiverPubkey: peerPubkey,
        content: wrappedRecipient.giftWrap['content']?.toString() ?? '',
        plaintext: replyText,
        timestamp: messageTs,
        status: 'sent',
        chatKey: chatKey,
        giftWrapId: wrappedRecipient.giftWrapId,
      ));
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      await chatsBox.put(chatKey, messages);

      await BgInbox.recordSentReply(peerPubkey);

      _broadcastToRelays([
        jsonEncode(['EVENT', wrappedRecipient.giftWrap]),
        jsonEncode(['EVENT', wrappedSelf.giftWrap]),
      ]);

      // Dismiss right away so the inline-reply spinner stops.
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_chatme'),
        ));
        await plugin.cancel(ChatNotificationHandler.notificationId(peerPubkey));
      } catch (_) {}
    } catch (e) {
      debugPrint('[BgChat] Send reply failed | $e');
    }
  }

  // ------------------------------------------------------------------ Helpers

  static String _chatKey(String pubkeyA, String pubkeyB) {
    final sorted = [pubkeyA, pubkeyB]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }

  static Future<void> _prepareHive() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(ChatMessageAdapter());
  }

  /// Opens a box owned by the main app without ever compacting its file.
  static Future<Box> _openBox(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box(name);
    return Hive.openBox(name, compactionStrategy: (_, __) => false);
  }

  /// Publishes [payloads] to every relay without waiting for the result, so the
  /// notification isolate is never blocked by slow relays.
  static void _broadcastToRelays(List<String> payloads) {
    for (final url in _relays) {
      try {
        final channel = WebSocketChannel.connect(Uri.parse(url));
        channel.ready.timeout(const Duration(seconds: 4)).then((_) async {
          for (final p in payloads) {
            channel.sink.add(p);
          }
          // Give the relay a moment to receive the events before closing.
          await Future.delayed(const Duration(milliseconds: 500));
          channel.sink.close();
        }).catchError((_) {});
      } catch (_) {}
    }
  }
}