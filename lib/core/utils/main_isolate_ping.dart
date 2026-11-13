// lib/core/utils/main_isolate_ping.dart
//
// Tells whether the main isolate is really listening on its notification port.
// A port name can stay registered after the main isolate is gone, so the
// notification-action isolate asks first and hands work to the app only when
// the app answers.

import 'dart:async';
import 'dart:isolate';

const String _pingType = 'PING';
const String _pongReply = 'PONG';

/// Pings [port] and waits up to [timeout] for the answer.
Future<bool> isMainIsolateReady(
  SendPort? port, {
  Duration timeout = const Duration(milliseconds: 700),
}) async {
  if (port == null) return false;

  final responsePort = ReceivePort();
  try {
    port.send({'type': _pingType, 'replyTo': responsePort.sendPort});
    final response = await responsePort.first.timeout(timeout);
    return response == _pongReply;
  } catch (_) {
    return false;
  } finally {
    responsePort.close();
  }
}

/// Answers a ping sent by [isMainIsolateReady]. Returns true when [message]
/// was a ping, so the caller can stop handling it.
bool answerPing(Object? message) {
  if (message is! Map || message['type'] != _pingType) return false;

  final replyPort = message['replyTo'];
  if (replyPort is SendPort) replyPort.send(_pongReply);
  return true;
}
