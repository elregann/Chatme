// nip17_dm_relays_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/nip17.dart';

void main() {
  test('DM relay list uses kind 10050 with one relay tag per relay', () {
    final tags = Nip17.dmRelayListTags([
      'wss://inbox.nostr.wine',
      'wss://myrelay.nostr1.com',
    ]);

    expect(Nip17.kindDmRelayList, 10050);
    expect(tags, [
      ['relay', 'wss://inbox.nostr.wine'],
      ['relay', 'wss://myrelay.nostr1.com'],
    ]);
  });

  test('DM relay list tags are empty for an empty relay list', () {
    expect(Nip17.dmRelayListTags([]), isEmpty);
  });
}
