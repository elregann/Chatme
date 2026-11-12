import 'dart:io';

import 'package:chatme/core/utils/bg_inbox.dart';
import 'package:chatme/core/utils/notification_entry.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationEntry entry(
  String message, {
  int timeMs = 0,
  String sender = 'Alice',
}) =>
    NotificationEntry(sender: sender, message: message, timeMs: timeMs);

Future<List<String>> messagesOf(String peer) async =>
    (await BgInbox.stackOf(peer)).map((e) => e.message).toList();

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notification_stack_test');
    BgInbox.baseDirectoryOverride = tempDir;
  });

  tearDown(() async {
    BgInbox.baseDirectoryOverride = null;
    await tempDir.delete(recursive: true);
  });

  group('NotificationEntry', () {
    test('survives a round trip through json', () {
      final restored = NotificationEntry.fromJson(
        entry('hello', timeMs: 1234, sender: 'Bob').toJson(),
      );

      expect(restored.sender, 'Bob');
      expect(restored.message, 'hello');
      expect(restored.timeMs, 1234);
    });

    test('rejects json with the wrong shape', () {
      expect(
        () => NotificationEntry.fromJson({'sender': 1, 'message': 'x', 'time': 0}),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('notification stack', () {
    test('an unread message is still there for the next notification', () async {
      await BgInbox.addToStack('alice', 'm1', entry('hello', timeMs: 1));

      // Swiping the notification away does not touch the stack.
      expect(await messagesOf('alice'), ['hello']);

      await BgInbox.addToStack('alice', 'm2', entry('hello again', timeMs: 2));

      expect(await messagesOf('alice'), ['hello', 'hello again']);
    });

    test('returns the oldest message first whatever the order of arrival', () async {
      await BgInbox.addToStack('alice', 'm3', entry('third', timeMs: 3));
      await BgInbox.addToStack('alice', 'm1', entry('first', timeMs: 1));
      await BgInbox.addToStack('alice', 'm2', entry('second', timeMs: 2));

      expect(await messagesOf('alice'), ['first', 'second', 'third']);
    });

    test('keeps the sender and the time of each message', () async {
      await BgInbox.addToStack(
        'alice',
        'm1',
        entry('hello', timeMs: 1234, sender: 'Alice'),
      );

      final stored = (await BgInbox.stackOf('alice')).single;
      expect(stored.sender, 'Alice');
      expect(stored.message, 'hello');
      expect(stored.timeMs, 1234);
    });

    test('showing the same message twice keeps a single entry', () async {
      await BgInbox.addToStack('alice', 'm1', entry('hello', timeMs: 1));
      await BgInbox.addToStack('alice', 'm1', entry('hello', timeMs: 1));

      expect(await messagesOf('alice'), ['hello']);
    });

    test('keeps only the newest messages up to the limit', () async {
      for (var i = 1; i <= 5; i++) {
        await BgInbox.addToStack(
          'alice',
          'm$i',
          entry('message $i', timeMs: i),
          keepNewest: 3,
        );
      }

      expect(await messagesOf('alice'), ['message 3', 'message 4', 'message 5']);
    });

    test('keeps ten messages per contact by default', () async {
      for (var i = 1; i <= 12; i++) {
        await BgInbox.addToStack('alice', 'm$i', entry('message $i', timeMs: i));
      }

      final messages = await messagesOf('alice');
      expect(messages.length, 10);
      expect(messages.first, 'message 3');
      expect(messages.last, 'message 12');
    });

    test('contacts have separate stacks', () async {
      await BgInbox.addToStack('alice', 'm1', entry('from alice', timeMs: 1));
      await BgInbox.addToStack('bob', 'm2', entry('from bob', timeMs: 2));

      expect(await messagesOf('alice'), ['from alice']);
      expect(await messagesOf('bob'), ['from bob']);
    });

    test('a contact whose id starts like another one is not mixed up', () async {
      await BgInbox.addToStack('ab', 'm1', entry('short id', timeMs: 1));
      await BgInbox.addToStack('abc', 'm2', entry('long id', timeMs: 2));

      expect(await messagesOf('ab'), ['short id']);
      expect(await messagesOf('abc'), ['long id']);
    });

    test('clearStack empties one contact and keeps the others', () async {
      await BgInbox.addToStack('alice', 'm1', entry('from alice', timeMs: 1));
      await BgInbox.addToStack('bob', 'm2', entry('from bob', timeMs: 2));

      await BgInbox.clearStack('alice');

      expect(await messagesOf('alice'), isEmpty);
      expect(await messagesOf('bob'), ['from bob']);
    });

    test('clearStack on an empty contact does nothing', () async {
      await BgInbox.clearStack('nobody');

      expect(await messagesOf('nobody'), isEmpty);
    });

    test('clearAllStacks empties every contact', () async {
      await BgInbox.addToStack('alice', 'm1', entry('from alice', timeMs: 1));
      await BgInbox.addToStack('bob', 'm2', entry('from bob', timeMs: 2));

      await BgInbox.clearAllStacks();

      expect(await BgInbox.stackSizes(), isEmpty);
    });

    test('stackSizes counts the messages of each contact', () async {
      await BgInbox.addToStack('alice', 'm1', entry('one', timeMs: 1));
      await BgInbox.addToStack('alice', 'm2', entry('two', timeMs: 2));
      await BgInbox.addToStack('bob', 'm3', entry('three', timeMs: 3));

      expect(await BgInbox.stackSizes(), {'alice': 2, 'bob': 1});
    });

    test('an unreadable entry is ignored', () async {
      await BgInbox.addToStack('alice', 'm1', entry('hello', timeMs: 1));
      final folder = Directory('${tempDir.path}/bg_inbox');
      await File('${folder.path}/n_alice_broken').writeAsString('not json');

      expect(await messagesOf('alice'), ['hello']);
    });

    test('a message id cannot write outside the inbox folder', () async {
      await BgInbox.addToStack('alice', '../../escape', entry('hello', timeMs: 1));

      final files = tempDir.listSync(recursive: true).whereType<File>();
      final inbox = '${tempDir.path}${Platform.pathSeparator}bg_inbox';
      expect(files.every((file) => file.path.startsWith(inbox)), isTrue);
      expect(await messagesOf('alice'), ['hello']);
    });

    test('does not mix with the unread ids kept for read receipts', () async {
      await BgInbox.addUnread('alice', 'rumor1');
      await BgInbox.addToStack('alice', 'm1', entry('hello', timeMs: 1));

      expect(await BgInbox.takeUnread('alice'), ['rumor1']);
      expect(await messagesOf('alice'), ['hello']);

      await BgInbox.addUnread('alice', 'rumor2');
      await BgInbox.clearStack('alice');
      await BgInbox.clearAllStacks();

      expect(await BgInbox.takeUnread('alice'), ['rumor2']);
    });
  });
}
