// lib/core/utils/background_call_signal.dart
//
// Sends a call "hangup" signal from the notification background isolate,
// when the main app is closed and RelayManager is not running.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../crypto/nip17.dart';

class BackgroundCallSignal {
  static const List<String> _relays = [
    'wss://nos.lol',
    'wss://relay.damus.io',
    'wss://relay.primal.net',
  ];

  static Future<void> sendHangup(String receiverPubkey) async {
    try {
      await Hive.initFlutter();
      final settingsBox = await Hive.openBox('settings');
      final myPrivkey = settingsBox.get('my_privkey', defaultValue: '') as String;
      final myPubkey = settingsBox.get('my_pubkey', defaultValue: '') as String;
      if (myPrivkey.isEmpty || myPubkey.isEmpty) return;
      await settingsBox.put(
        'declined_call_$receiverPubkey',
        DateTime.now().millisecondsSinceEpoch,
      );

      final wrapped = await Nip17.wrap(
        plaintext: jsonEncode({'type': 'hangup'}),
        senderPrivkey: myPrivkey,
        senderPubkey: myPubkey,
        receiverPubkey: receiverPubkey,
        kind: Nip17.kindCallSignal,
        customTags: [
          ['p', receiverPubkey],
        ],
      );
      final payload = jsonEncode(['EVENT', wrapped.giftWrap]);

      final channels = <WebSocketChannel>[];
      for (final url in _relays) {
        try {
          final channel = WebSocketChannel.connect(Uri.parse(url));
          await channel.ready.timeout(const Duration(seconds: 4));
          channel.sink.add(payload);
          channels.add(channel);
        } catch (e) {
          debugPrint('[BgCall] Relay $url failed | $e');
        }
      }

      // Give the relays a moment to receive the event before closing.
      await Future.delayed(const Duration(seconds: 1));
      for (final channel in channels) {
        channel.sink.close();
      }
      debugPrint('[BgCall] Hangup sent via ${channels.length} relay(s)');
    } catch (e) {
      debugPrint('[BgCall] Hangup failed | $e');
    }
  }
}