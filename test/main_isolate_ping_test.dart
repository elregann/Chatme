import 'dart:async';
import 'dart:isolate';

import 'package:chatme/core/utils/main_isolate_ping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const shortWait = Duration(milliseconds: 50);

  group('isMainIsolateReady', () {
    test('is true when the port answers the ping', () async {
      final mainPort = ReceivePort();
      addTearDown(mainPort.close);
      mainPort.listen(answerPing);

      expect(await isMainIsolateReady(mainPort.sendPort), isTrue);
    });

    test('is false when there is no port', () async {
      expect(await isMainIsolateReady(null), isFalse);
    });

    test('is false when nobody answers', () async {
      final silentPort = ReceivePort();
      addTearDown(silentPort.close);
      silentPort.listen((_) {});

      expect(await isMainIsolateReady(silentPort.sendPort, timeout: shortWait), isFalse);
    });

    test('is false when the port was closed but is still known', () async {
      final gonePort = ReceivePort();
      final staleSendPort = gonePort.sendPort;
      gonePort.close();

      expect(await isMainIsolateReady(staleSendPort, timeout: shortWait), isFalse);
    });

    test('is false when the answer is not the expected one', () async {
      final oddPort = ReceivePort();
      addTearDown(oddPort.close);
      oddPort.listen((message) {
        final replyTo = (message as Map)['replyTo'];
        if (replyTo is SendPort) replyTo.send('SOMETHING ELSE');
      });

      expect(await isMainIsolateReady(oddPort.sendPort), isFalse);
    });

    test('waits no longer than the timeout', () async {
      final silentPort = ReceivePort();
      addTearDown(silentPort.close);
      silentPort.listen((_) {});

      final stopwatch = Stopwatch()..start();
      await isMainIsolateReady(silentPort.sendPort, timeout: shortWait);
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('answerPing', () {
    test('answers a ping on the port it names and reports it was a ping', () async {
      final replyPort = ReceivePort();
      addTearDown(replyPort.close);

      final handled = answerPing({'type': 'PING', 'replyTo': replyPort.sendPort});

      expect(handled, isTrue);
      expect(await replyPort.first.timeout(const Duration(seconds: 1)), 'PONG');
    });

    test('a ping without a reply port is still a ping and does not throw', () {
      expect(answerPing({'type': 'PING'}), isTrue);
      expect(answerPing({'type': 'PING', 'replyTo': 'not a port'}), isTrue);
    });

    test('a notification action is not a ping and gets no answer', () async {
      final replyPort = ReceivePort();
      addTearDown(replyPort.close);

      final handled = answerPing({
        'actionId': 'REPLY_ACTION',
        'input': 'hello',
        'payload': 'alice',
        'replyTo': replyPort.sendPort,
      });

      expect(handled, isFalse);
      await expectLater(
        replyPort.first.timeout(shortWait),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('anything that is not a map is not a ping', () {
      expect(answerPing('PING'), isFalse);
      expect(answerPing(null), isFalse);
      expect(answerPing(42), isFalse);
    });
  });
}
