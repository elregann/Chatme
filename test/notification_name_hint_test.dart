import 'package:chatme/chat_notification_handler.dart';
import 'package:chatme/core/utils/key_utils.dart';
import 'package:chatme/core/utils/notification_profile.dart';
import 'package:chatme/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pubkey =
      '1111111111111111111111111111111111111111111111111111111111111111';
  final stub = KeyUtils.formatDisplayName(pubkey);

  Contact contact(String name, {bool saved = false}) =>
      Contact(pubkey: pubkey, name: name, isSaved: saved);

  group('NotificationProfile.pickName', () {
    test('an unsaved contact with a placeholder name takes the hint', () {
      expect(
        NotificationProfile.pickName(
          pubkey: pubkey,
          contact: contact(stub),
          hint: 'Edwards',
        ),
        'Edwards',
      );
    });

    test('an unsaved contact with an older name takes the fresher hint', () {
      expect(
        NotificationProfile.pickName(
          pubkey: pubkey,
          contact: contact('Ed'),
          hint: 'Edwards',
        ),
        'Edwards',
      );
    });

    test('a name the user saved always wins over the hint', () {
      expect(
        NotificationProfile.pickName(
          pubkey: pubkey,
          contact: contact('Boss', saved: true),
          hint: 'Edwards',
        ),
        'Boss',
      );
    });

    test('a stranger without a contact row keeps the npub stub', () {
      expect(
        NotificationProfile.pickName(pubkey: pubkey, hint: 'Edwards'),
        stub,
      );
    });

    test('no hint keeps the local name', () {
      expect(
        NotificationProfile.pickName(pubkey: pubkey, contact: contact('Ed')),
        'Ed',
      );
      expect(
        NotificationProfile.pickName(pubkey: pubkey, contact: contact(stub)),
        stub,
      );
    });

    test('placeholder hints are ignored', () {
      for (final hint in ['', '   ', 'npub1abcdef', 'User 1234', pubkey]) {
        expect(
          NotificationProfile.pickName(
            pubkey: pubkey,
            contact: contact('Ed'),
            hint: hint,
          ),
          'Ed',
          reason: 'hint "$hint"',
        );
      }
    });
  });

  group('NotificationProfile.cleanNameHint', () {
    test('trims and collapses whitespace and control characters', () {
      expect(
        NotificationProfile.cleanNameHint('  Ed\nwards\t\u0007x ', pubkey),
        'Ed wards x',
      );
    });

    test('caps a very long name at 64 characters', () {
      final cleaned = NotificationProfile.cleanNameHint('a' * 100, pubkey);
      expect(cleaned, 'a' * 64);
    });

    test('does not split a character made of two code units', () {
      final cleaned = NotificationProfile.cleanNameHint('😀' * 70, pubkey)!;
      expect(cleaned.runes.length, 64);
      expect(cleaned.runes.every((r) => r == 0x1F600), isTrue);
    });

    test('returns null for null input', () {
      expect(NotificationProfile.cleanNameHint(null, pubkey), isNull);
    });
  });

  group('ChatNotificationHandler.pushNameHint', () {
    test('a chat push hints with its sender name', () {
      expect(
        ChatNotificationHandler.pushNameHint(
          {'type': 'chat', 'senderName': 'Edwards'},
        ),
        'Edwards',
      );
    });

    test('a call push hints with its caller name', () {
      expect(
        ChatNotificationHandler.pushNameHint(
          {'type': 'call', 'senderName': 'Edwards'},
        ),
        'Edwards',
      );
    });

    test('a cancel push hints with its caller name', () {
      expect(
        ChatNotificationHandler.pushNameHint(
          {'type': 'call_cancel', 'senderName': 'Edwards'},
        ),
        'Edwards',
      );
    });

    test('a legacy cancel push with the ChatMe label never hints', () {
      expect(
        ChatNotificationHandler.pushNameHint(
          {'type': 'call_cancel', 'senderName': 'ChatMe'},
        ),
        isNull,
      );
    });

    test('a missing, blank or non text name gives no hint', () {
      expect(ChatNotificationHandler.pushNameHint({'type': 'chat'}), isNull);
      expect(
        ChatNotificationHandler.pushNameHint({'senderName': '  '}),
        isNull,
      );
      expect(
        ChatNotificationHandler.pushNameHint({'senderName': 42}),
        isNull,
      );
    });
  });

  group('ChatNotificationHandler.pushAvatarHint & cleanAvatarHint', () {
    test('a valid https avatar url is returned as hint', () {
      const url = 'https://example.com/avatar.jpg';
      expect(
        ChatNotificationHandler.pushAvatarHint({'senderAvatar': url}),
        url,
      );
      expect(
        NotificationProfile.cleanAvatarHint('  $url  '),
        url,
      );
    });

    test('non-https or malformed urls are rejected', () {
      for (final bad in [
        '',
        '   ',
        'http://example.com/avatar.jpg',
        'ftp://example.com/avatar.jpg',
        'not a url',
        'https://',
      ]) {
        expect(
          ChatNotificationHandler.pushAvatarHint({'senderAvatar': bad}),
          isNull,
          reason: 'avatar "$bad"',
        );
        expect(
          NotificationProfile.cleanAvatarHint(bad),
          isNull,
          reason: 'cleanAvatarHint "$bad"',
        );
      }
    });

    test('null or missing avatar gives no hint', () {
      expect(ChatNotificationHandler.pushAvatarHint({}), isNull);
      expect(NotificationProfile.cleanAvatarHint(null), isNull);
    });
  });
}
