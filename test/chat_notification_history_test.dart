import 'package:chatme/core/utils/chat_notification_history.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationEntry entry(String message, {int timeMs = 0}) => NotificationEntry(
      sender: 'Alice',
      message: message,
      timeMs: timeMs,
    );

List<String> messagesOf(ChatNotificationHistory history, String contact) =>
    history.entriesFor(contact).map((e) => e.message).toList();

void main() {
  group('ChatNotificationHistory', () {
    test('stacks messages while the notification is still shown', () {
      final history = ChatNotificationHistory();

      history.add('alice', entry('halo'), previousStillShown: true);
      history.add('alice', entry('apa kabar?'), previousStillShown: true);

      expect(messagesOf(history, 'alice'), ['halo', 'apa kabar?']);
    });

    test('starts over when the previous notification is gone', () {
      final history = ChatNotificationHistory();

      history.add('alice', entry('halo'), previousStillShown: true);
      history.add('alice', entry('apa kabar?'), previousStillShown: false);

      expect(messagesOf(history, 'alice'), ['apa kabar?']);
    });

    test('the first message of a contact is kept either way', () {
      final shown = ChatNotificationHistory()
        ..add('alice', entry('halo'), previousStillShown: true);
      final gone = ChatNotificationHistory()
        ..add('alice', entry('halo'), previousStillShown: false);

      expect(messagesOf(shown, 'alice'), ['halo']);
      expect(messagesOf(gone, 'alice'), ['halo']);
    });

    test('keeps only the newest messages up to the cap', () {
      final history = ChatNotificationHistory(maxPerContact: 3);

      for (var i = 1; i <= 5; i++) {
        history.add('alice', entry('m$i'), previousStillShown: true);
      }

      expect(messagesOf(history, 'alice'), ['m3', 'm4', 'm5']);
    });

    test('defaults to ten messages per contact', () {
      final history = ChatNotificationHistory();

      for (var i = 1; i <= 12; i++) {
        history.add('alice', entry('m$i'), previousStillShown: true);
      }

      expect(history.entriesFor('alice').length, 10);
      expect(history.entriesFor('alice').first.message, 'm3');
      expect(history.entriesFor('alice').last.message, 'm12');
    });

    test('keeps the sender and the time of each entry', () {
      final history = ChatNotificationHistory();

      history.add('alice', entry('halo', timeMs: 1234), previousStillShown: true);

      final stored = history.entriesFor('alice').single;
      expect(stored.sender, 'Alice');
      expect(stored.message, 'halo');
      expect(stored.timeMs, 1234);
    });

    test('contacts are independent of each other', () {
      final history = ChatNotificationHistory();

      history.add('alice', entry('halo'), previousStillShown: true);
      history.add('bob', entry('hai'), previousStillShown: true);
      history.add('alice', entry('apa kabar?'), previousStillShown: false);

      expect(messagesOf(history, 'alice'), ['apa kabar?']);
      expect(messagesOf(history, 'bob'), ['hai']);
    });

    test('clear removes one contact and keeps the others', () {
      final history = ChatNotificationHistory();
      history.add('alice', entry('halo'), previousStillShown: true);
      history.add('bob', entry('hai'), previousStillShown: true);

      history.clear('alice');

      expect(history.entriesFor('alice'), isEmpty);
      expect(messagesOf(history, 'bob'), ['hai']);
    });

    test('clearAll removes everything', () {
      final history = ChatNotificationHistory();
      history.add('alice', entry('halo'), previousStillShown: true);
      history.add('bob', entry('hai'), previousStillShown: true);

      history.clearAll();

      expect(history.contactCount, 0);
      expect(history.messageCount, 0);
    });

    test('counts contacts and messages', () {
      final history = ChatNotificationHistory();
      expect(history.contactCount, 0);
      expect(history.messageCount, 0);

      history.add('alice', entry('halo'), previousStillShown: true);
      history.add('alice', entry('apa kabar?'), previousStillShown: true);
      history.add('bob', entry('hai'), previousStillShown: true);

      expect(history.contactCount, 2);
      expect(history.messageCount, 3);
    });

    test('an unknown contact has no entries', () {
      expect(ChatNotificationHistory().entriesFor('nobody'), isEmpty);
    });

    test('the returned entries cannot change the history', () {
      final history = ChatNotificationHistory();
      history.add('alice', entry('halo'), previousStillShown: true);

      final entries = history.entriesFor('alice');

      expect(() => entries.add(entry('x')), throwsUnsupportedError);
      expect(messagesOf(history, 'alice'), ['halo']);
    });
  });
}
