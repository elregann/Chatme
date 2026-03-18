// nostr_service.dart

import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';

class NostrHelpers {
  static String generateEventId(Map<String, dynamic> event) {
    try {
      final serialized = jsonEncode([
        0,
        event['pubkey'],
        event['created_at'],
        event['kind'],
        event['tags'],
        event['content']
      ]);
      return sha256.convert(utf8.encode(serialized)).toString();
    } catch (e) {
      rethrow;
    }
  }

  static String serializeEvent(Map<String, dynamic> event) {
    return jsonEncode([
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content']
    ]);
  }

  static String getChatKey(String pubkey1, String pubkey2) {
    final sorted = [pubkey1, pubkey2]..sort();
    return 'chat_${sorted[0]}_${sorted[1]}';
  }
}

class Lock {
  bool _locked = false;
  final List<Completer<void>> _waiting = [];

  Future<T> synchronized<T>(Future<T> Function() task) async {
    while (_locked) {
      final completer = Completer<void>();
      _waiting.add(completer);
      await completer.future;
    }

    _locked = true;
    try {
      return await task();
    } finally {
      _locked = false;
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      }
    }
  }
}