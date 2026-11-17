// handoff_unread_test.dart
//
// Regression guard for the background-notification "Mark as Read" badge bug:
// the FCM handoff must not re-arm an unread badge for a message that was
// already read while it was still waiting in the ciphertext spool.

import 'package:chatme/main.dart';
import 'package:flutter_test/flutter_test.dart';

bool muted({
  bool isFromMe = false,
  bool currentlyOpen = false,
  bool syncActive = false,
  required bool wasNew,
  bool alreadyRead = false,
}) =>
    shouldMuteHandoffUnread(
      isFromMe: isFromMe,
      currentlyOpen: currentlyOpen,
      syncActive: syncActive,
      wasNew: wasNew,
      alreadyRead: alreadyRead,
    );

void main() {
  group('FCM handoff unread rule', () {
    test('a new message that was already read from a background tap stays muted',
        () {
      // This is the bug: wasNew is true, but saveMessage found the r_ marker
      // and stored the message with status read.
      expect(muted(wasNew: true, alreadyRead: true), isTrue);
    });

    test('a genuinely new unread message raises the badge', () {
      expect(muted(wasNew: true), isFalse);
    });

    test('a duplicate from relay or spool stays muted', () {
      expect(muted(wasNew: false), isTrue);
      expect(muted(wasNew: false, alreadyRead: true), isTrue);
    });

    test('messages from me never raise the badge', () {
      expect(muted(wasNew: true, isFromMe: true), isTrue);
    });

    test('a message in the currently open chat never raises the badge', () {
      expect(muted(wasNew: true, currentlyOpen: true), isTrue);
    });

    test('initial sync never raises the badge', () {
      expect(muted(wasNew: true, syncActive: true), isTrue);
    });
  });
}
