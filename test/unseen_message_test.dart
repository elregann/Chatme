import 'package:chatme/core/utils/unseen_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldCountUnseen', () {
    test('counts a message from the open contact while scrolled up', () {
      expect(
        shouldCountUnseen(peerPubkey: 'a', openPubkey: 'a', nearBottom: false),
        isTrue,
      );
    });

    test('does not count while near the bottom', () {
      expect(
        shouldCountUnseen(peerPubkey: 'a', openPubkey: 'a', nearBottom: true),
        isFalse,
      );
    });

    test('does not count messages from another contact', () {
      expect(
        shouldCountUnseen(peerPubkey: 'b', openPubkey: 'a', nearBottom: false),
        isFalse,
      );
    });
  });
}
