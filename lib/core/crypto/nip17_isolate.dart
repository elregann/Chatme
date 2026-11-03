// lib/core/crypto/nip17_isolate.dart
//
// Offloads NIP-17 gift-wrap crypto to a background isolate.
//
// Wrapping/unwrapping a gift wrap performs several ECDH scalar
// multiplications, NIP-44 encryption/decryption and Schnorr signing. The
// pure-Dart implementation takes tens of milliseconds per operation, which is
// enough to drop frames when it runs on the UI isolate while a call is being
// set up or torn down (every ICE signal is gift-wrapped).
//
// `compute` runs the callback in a short-lived isolate on native platforms and
// transparently falls back to running inline on the web, where isolates are not
// available.
//
// Only plain maps/strings/ints cross the isolate boundary so both platforms
// stay happy, and the result is rebuilt into the usual NIP-17 value objects.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nip17.dart';

class Nip17Isolate {
  Nip17Isolate._();

  /// A relay burst can deliver many gift wraps at once. Spawning one isolate
  /// per message would cause an isolate storm on low-end devices, while fully
  /// serializing could delay an incoming call offer behind a long backlog.
  /// A small concurrency cap keeps decryption off the UI thread and leaves a
  /// slot free for time-sensitive signals.
  static const int _maxConcurrentUnwraps = 2;
  static int _activeUnwraps = 0;
  static final List<Completer<void>> _unwrapWaiters = <Completer<void>>[];

  static Future<void> _acquireUnwrapSlot() {
    if (_activeUnwraps < _maxConcurrentUnwraps) {
      _activeUnwraps++;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _unwrapWaiters.add(completer);
    return completer.future;
  }

  static void _releaseUnwrapSlot() {
    if (_unwrapWaiters.isNotEmpty) {
      // Hand the slot directly to the next waiter.
      _unwrapWaiters.removeAt(0).complete();
    } else {
      _activeUnwraps--;
    }
  }

  /// Same contract as [Nip17.wrap], but the CPU-heavy work runs off the UI
  /// isolate.
  static Future<Nip17Wrapped> wrap({
    required String plaintext,
    required String senderPrivkey,
    required String senderPubkey,
    required String receiverPubkey,
    int kind = Nip17.kindRumor,
    List<List<String>>? customTags,
  }) async {
    final result = await compute(_wrapInIsolate, <String, dynamic>{
      'plaintext': plaintext,
      'senderPrivkey': senderPrivkey,
      'senderPubkey': senderPubkey,
      'receiverPubkey': receiverPubkey,
      'kind': kind,
      'customTags': customTags,
    });

    return Nip17Wrapped(
      giftWrap: Map<String, dynamic>.from(result['giftWrap'] as Map),
      giftWrapId: result['giftWrapId'] as String,
      rumorId: result['rumorId'] as String,
      rumorTimestamp: result['rumorTimestamp'] as int,
    );
  }

  /// Same contract as [Nip17.unwrap], but the CPU-heavy work runs off the UI
  /// isolate.
  static Future<Nip17Result> unwrap({
    required Map<String, dynamic> giftWrapEvent,
    required String receiverPrivkey,
    required String receiverPubkey,
  }) async {
    await _acquireUnwrapSlot();
    try {
      final result = await compute(_unwrapInIsolate, <String, dynamic>{
        'giftWrapEvent': giftWrapEvent,
        'receiverPrivkey': receiverPrivkey,
        'receiverPubkey': receiverPubkey,
      });

      return Nip17Result(
        plaintext: result['plaintext'] as String,
        senderPubkey: result['senderPubkey'] as String,
        receiverPubkey: result['receiverPubkey'] as String,
        timestamp: result['timestamp'] as int,
        rumorId: result['rumorId'] as String,
        replyToId: result['replyToId'] as String?,
        rumorTags: (result['rumorTags'] as List)
            .map<List<String>>(
              (tag) => (tag as List).map((value) => value.toString()).toList(),
            )
            .toList(),
        rumorKind: result['rumorKind'] as int,
      );
    } finally {
      _releaseUnwrapSlot();
    }
  }
}

Future<Map<String, dynamic>> _wrapInIsolate(Map<String, dynamic> args) async {
  final wrapped = await Nip17.wrap(
    plaintext: args['plaintext'] as String,
    senderPrivkey: args['senderPrivkey'] as String,
    senderPubkey: args['senderPubkey'] as String,
    receiverPubkey: args['receiverPubkey'] as String,
    kind: args['kind'] as int,
    customTags: (args['customTags'] as List?)
        ?.map<List<String>>(
          (tag) => (tag as List).map((value) => value.toString()).toList(),
        )
        .toList(),
  );

  return <String, dynamic>{
    'giftWrap': wrapped.giftWrap,
    'giftWrapId': wrapped.giftWrapId,
    'rumorId': wrapped.rumorId,
    'rumorTimestamp': wrapped.rumorTimestamp,
  };
}

Future<Map<String, dynamic>> _unwrapInIsolate(Map<String, dynamic> args) async {
  final result = await Nip17.unwrap(
    giftWrapEvent: Map<String, dynamic>.from(args['giftWrapEvent'] as Map),
    receiverPrivkey: args['receiverPrivkey'] as String,
    receiverPubkey: args['receiverPubkey'] as String,
  );

  return <String, dynamic>{
    'plaintext': result.plaintext,
    'senderPubkey': result.senderPubkey,
    'receiverPubkey': result.receiverPubkey,
    'timestamp': result.timestamp,
    'rumorId': result.rumorId,
    'replyToId': result.replyToId,
    'rumorTags': result.rumorTags,
    'rumorKind': result.rumorKind,
  };
}
