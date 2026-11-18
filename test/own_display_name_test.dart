// own_display_name_test.dart
//
// The name shown for our own account must follow the global ID. A stored copy
// went stale on restored accounts: after Disconnect ID the old username stayed.

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

  test('shows the username while a global ID is connected', () {
    settings.myNip05 = 'ujes@chatme';

    expect(settings.myName, 'ujes');
  });

  test('is empty before an account is loaded', () {
    settings.myPubkey = '';

    expect(settings.myName, isEmpty);
  });

  test('falls back to the npub form without a global ID', () {
    expect(settings.myName, AppSettings.formatDisplayName(pubkey));
  });

  test('releasing the global ID drops the old username', () async {
    settings.myNip05 = 'ujes@chatme';
    expect(settings.myName, 'ujes');

    settings.myNip05 = '';

    expect(settings.myName, isNot('ujes'));
    expect(settings.myName, AppSettings.formatDisplayName(pubkey));
  });
}
