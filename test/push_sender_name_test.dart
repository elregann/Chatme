// push_sender_name_test.dart
//
// The name pushed with a message or call is read by the receiver while its app
// is closed. It must carry our global ID name even though no contact row exists
// for our own pubkey.

import 'package:chatme/relay_manager.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final settings = AppSettings.instance;
  final pubkey = '${'0' * 63}1';

  setUp(() {
    settings.myPubkey = pubkey;
    settings.myNip05 = '';
    settings.myPhotoUrl = '';
  });

  tearDown(() {
    settings.myPubkey = '';
    settings.myNip05 = '';
    settings.myPhotoUrl = '';
  });

  test('the pushed name is the global ID username', () {
    settings.myNip05 = 'edwards@chatme';

    expect(RelayManager().currentSenderName(), 'edwards');
  });

  test('without a global ID the pushed name is the npub stub', () {
    expect(
      RelayManager().currentSenderName(),
      AppSettings.formatDisplayName(pubkey),
    );
  });

  test('a released global ID stops being pushed', () {
    settings.myNip05 = 'edwards@chatme';
    expect(RelayManager().currentSenderName(), 'edwards');

    settings.myNip05 = '';

    expect(RelayManager().currentSenderName(), isNot('edwards'));
  });

  group('RelayManager.currentSenderAvatar', () {
    test('uses AppSettings.myPhotoUrl when present', () {
      settings.myPhotoUrl = 'https://nostr.build/i/me.png';
      final avatar = RelayManager().currentSenderAvatar();
      expect(avatar, isNotNull);
      expect(avatar, contains('https://wsrv.nl/?url='));
      expect(avatar, contains('nostr.build'));
    });

    test('returns null when no photo is set', () {
      settings.myPhotoUrl = '';
      expect(RelayManager().currentSenderAvatar(), isNull);
    });
  });

  group('RelayManager.buildAvatarThumbnailUrl', () {
    test('wraps raw photo url in lightweight wsrv.nl thumbnail', () {
      const original = 'https://nostr.build/i/pfp.jpg';
      final thumb = RelayManager.buildAvatarThumbnailUrl(original);
      expect(thumb, contains('https://wsrv.nl/?url='));
      expect(thumb, contains('w=128'));
      expect(thumb, contains('h=128'));
      expect(thumb, contains('output=webp'));
    });

    test('does not double wrap an already-wrapped thumbnail url', () {
      const wrapped = 'https://wsrv.nl/?url=https%3A%2F%2Fnostr.build%2Fi%2Fpfp.jpg&w=128&h=128&fit=cover&output=webp&q=75';
      expect(RelayManager.buildAvatarThumbnailUrl(wrapped), wrapped);
    });

    test('empty url returns empty string', () {
      expect(RelayManager.buildAvatarThumbnailUrl(''), '');
      expect(RelayManager.buildAvatarThumbnailUrl('   '), '');
    });
  });
}
