// directory_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/crypto/nostr_protocol.dart';
import 'app_settings.dart';
import 'nostr_service.dart';

enum DirectoryResult { ok, taken, failed }

class DirectoryService {
  static const String baseUrl = 'https://chatme-directory.cintanyanessa.workers.dev';
  static const Duration _timeout = Duration(seconds: 15);

  static String _authHeader(String url, String action, {String? name}) {
    final pubkey = AppSettings.instance.myPubkey;
    final privkey = AppSettings.instance.myPrivkey;
    if (pubkey.isEmpty || privkey.isEmpty) {
      throw Exception('Missing keys');
    }

    final unsignedEvent = <String, dynamic>{
      'kind': 27235,
      'pubkey': pubkey,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'tags': [
        ['u', url],
        ['method', 'POST'],
        ['action', action],
        if (name != null) ['name', name],
      ],
      'content': '',
    };

    final eventId = NostrHelpers.generateEventId(unsignedEvent);
    final signature = NostrSigner.sign(eventId, privkey);
    final signedEvent = {...unsignedEvent, 'id': eventId, 'sig': signature};
    return 'Nostr ${base64Url.encode(utf8.encode(jsonEncode(signedEvent)))}';
  }

  static Future<DirectoryResult> claim(String name) async {
    const url = '$baseUrl/claim';
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': _authHeader(url, 'claim', name: name),
            },
            body: jsonEncode({'name': name}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) return DirectoryResult.ok;
      if (response.statusCode == 409) return DirectoryResult.taken;
      debugPrint('[Directory] claim failed | ${response.statusCode} ${response.body}');
      return DirectoryResult.failed;
    } catch (e) {
      debugPrint('[Directory] claim failed | $e');
      return DirectoryResult.failed;
    }
  }

  static Future<void> release() async {
    const url = '$baseUrl/release';
    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': _authHeader(url, 'release'),
          },
          body: '{}',
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Directory release failed (${response.statusCode})');
    }
  }
}
