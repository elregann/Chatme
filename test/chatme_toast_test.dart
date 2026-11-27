import 'dart:async';

import 'package:chatme/services/chatme_toast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => ChatmeToast.useSender(null));

  test('forwards the exact message to the system toast sender', () async {
    final sent = <String>[];
    final delivered = Completer<void>();
    ChatmeToast.useSender((message) async {
      sent.add(message);
      delivered.complete();
      return true;
    });

    ChatmeToast.show('Saved to album');
    await delivered.future;

    expect(sent, ['Saved to album']);
  });

  test('keeps messages in order when shown repeatedly', () async {
    final sent = <String>[];
    final delivered = Completer<void>();
    ChatmeToast.useSender((message) async {
      sent.add(message);
      if (sent.length == 2) delivered.complete();
      return false;
    });

    ChatmeToast.show('First');
    ChatmeToast.show('Second');
    await delivered.future;

    expect(sent, ['First', 'Second']);
  });

  test('does not propagate a failed toast', () async {
    final attempted = Completer<void>();
    ChatmeToast.useSender((_) async {
      attempted.complete();
      throw StateError('toast channel unavailable');
    });

    ChatmeToast.show('Still fine');
    await attempted.future;
    await Future<void>.delayed(Duration.zero);
  });
}
