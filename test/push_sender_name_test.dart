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
  });

  tearDown(() {
    settings.myPubkey = '';
    settings.myNip05 = '';
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
}
