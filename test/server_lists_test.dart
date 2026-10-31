// server_lists_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/blossom_service.dart';
import 'package:chatme/services/server_lists.dart';

void main() {
  group('relay addresses', () {
    test('adds wss:// when it is missing', () {
      expect(ServerAddress.relay('relay.damus.io'), 'wss://relay.damus.io');
    });

    test('lower cases the host, trims and drops the trailing slash', () {
      expect(ServerAddress.relay('  wss://Relay.Damus.IO/  '), 'wss://relay.damus.io');
    });

    test('keeps a port and a path', () {
      expect(
        ServerAddress.relay('wss://relay.example.com:8443/nostr/'),
        'wss://relay.example.com:8443/nostr',
      );
    });

    test('refuses what is not a usable address', () {
      const bad = [
        '',
        '   ',
        'wss://',
        'ws://relay.example.com',
        'https://relay.example.com',
        'wss://localhost',
        'wss://app.localhost',
        'wss://127.0.0.1',
        'wss://192.168.1.5',
        'wss://[::1]',
        'wss://nodot',
        'wss://printer.local',
        'wss://router.lan',
        'wss://user:pass@relay.example.com',
        'wss://relay.example.com?x=1',
        'wss://relay.example.com#top',
        'wss://re lay.example.com',
        'wss://-bad.example.com',
        'wss://bad-.example.com',
        'wss://relay..example.com',
        'wss://1.2.3.456',
      ];
      for (final text in bad) {
        expect(ServerAddress.relay(text), isNull, reason: text);
      }
    });

    test('refuses an address that is far too long', () {
      expect(ServerAddress.relay('wss://${'a' * 300}.example.com'), isNull);
    });
  });

  group('file server addresses', () {
    test('adds https:// when it is missing', () {
      expect(ServerAddress.blossom('blossom.ditto.pub'), 'https://blossom.ditto.pub');
    });

    test('drops the trailing slash', () {
      expect(ServerAddress.blossom('https://nostr.download/'), 'https://nostr.download');
    });

    test('only accepts https', () {
      expect(ServerAddress.blossom('http://files.example.com'), isNull);
      expect(ServerAddress.blossom('wss://files.example.com'), isNull);
    });

    test('refuses local and raw IP addresses', () {
      expect(ServerAddress.blossom('https://localhost:3000'), isNull);
      expect(ServerAddress.blossom('https://10.0.0.2'), isNull);
    });
  });

  group('adding', () {
    const start = ['wss://nos.lol'];

    test('appends the normalized address at the end', () {
      final edit = ServerLists.add(start, 'Relay.Damus.io/',
          normalize: ServerAddress.relay, max: 5);
      expect(edit.change, ListChange.ok);
      expect(edit.list, ['wss://nos.lol', 'wss://relay.damus.io']);
    });

    test('does not change the list it was given', () {
      ServerLists.add(start, 'relay.damus.io', normalize: ServerAddress.relay, max: 5);
      expect(start, ['wss://nos.lol']);
    });

    test('refuses a duplicate, even written differently', () {
      final edit = ServerLists.add(start, 'WSS://NOS.LOL/', normalize: ServerAddress.relay, max: 5);
      expect(edit.change, ListChange.duplicate);
      expect(edit.list, start);
    });

    test('refuses an address that is already in the other list', () {
      final edit = ServerLists.add(
        start,
        'relay.damus.io',
        normalize: ServerAddress.relay,
        max: 5,
        taken: ['wss://relay.damus.io'],
      );
      expect(edit.change, ListChange.duplicate);
    });

    test('refuses an invalid address', () {
      final edit = ServerLists.add(start, 'ws://insecure.example.com',
          normalize: ServerAddress.relay, max: 5);
      expect(edit.change, ListChange.invalid);
      expect(edit.list, start);
    });

    test('refuses when the list is full', () {
      final edit = ServerLists.add(start, 'relay.damus.io', normalize: ServerAddress.relay, max: 1);
      expect(edit.change, ListChange.full);
      expect(edit.list, start);
    });
  });

  group('removing', () {
    const list = ['wss://a.example.com', 'wss://b.example.com'];

    test('takes one address out', () {
      final edit = ServerLists.remove(list, 'wss://a.example.com');
      expect(edit.change, ListChange.ok);
      expect(edit.list, ['wss://b.example.com']);
    });

    test('does not change the list it was given', () {
      ServerLists.remove(list, 'wss://a.example.com');
      expect(list, hasLength(2));
    });

    test('says so when the address is not there', () {
      final edit = ServerLists.remove(list, 'wss://c.example.com');
      expect(edit.change, ListChange.missing);
      expect(edit.list, list);
    });

    test('keeps the minimum number of entries', () {
      final edit = ServerLists.remove(['wss://a.example.com'], 'wss://a.example.com', minimum: 1);
      expect(edit.change, ListChange.tooFew);
      expect(edit.list, ['wss://a.example.com']);
    });

    test('may empty a list when no minimum is set', () {
      final edit = ServerLists.remove(['wss://a.example.com'], 'wss://a.example.com');
      expect(edit.change, ListChange.ok);
      expect(edit.list, isEmpty);
    });
  });

  group('defaults', () {
    test('are all valid addresses already in normal form', () {
      for (final url in [...RelayDefaults.inbox, ...RelayDefaults.other]) {
        expect(ServerAddress.relay(url), url);
      }
      for (final url in BlossomService.defaultServers) {
        expect(ServerAddress.blossom(url), url);
      }
    });

    test('the two relay lists do not share a relay', () {
      expect(RelayDefaults.inbox.toSet().intersection(RelayDefaults.other.toSet()), isEmpty);
    });

    test('together they are the relays Chatme has always used', () {
      expect(
        {...RelayDefaults.inbox, ...RelayDefaults.other},
        {
          'wss://nos.lol',
          'wss://auth.nostr1.com',
          'wss://messaging.coracle.social',
          'wss://relay.damus.io',
          'wss://relay.primal.net',
        },
      );
    });

    test('the inbox defaults are the ones announced so far', () {
      expect(RelayDefaults.inbox, ['wss://auth.nostr1.com', 'wss://nos.lol']);
    });

    test('the defaults fit inside the limits', () {
      expect(RelayDefaults.inbox.length, lessThanOrEqualTo(ListLimits.inboxRecommended));
      expect(RelayDefaults.inbox.length, greaterThanOrEqualTo(ListLimits.inboxMin));
      expect(RelayDefaults.other.length, lessThanOrEqualTo(ListLimits.otherMax));
      expect(BlossomService.defaultServers.length, lessThanOrEqualTo(ListLimits.blossomMax));
    });
  });

  group('showing', () {
    test('displayHost drops the scheme and the trailing slash', () {
      expect(ServerAddress.displayHost('wss://relay.damus.io'), 'relay.damus.io');
      expect(ServerAddress.displayHost('https://nostr.download/'), 'nostr.download');
      expect(ServerAddress.displayHost('wss://relay.example.com:8443/nostr'), 'relay.example.com:8443/nostr');
    });

    test('isDefault compares with a list of defaults', () {
      expect(ServerLists.isDefault('wss://nos.lol', RelayDefaults.inbox), isTrue);
      expect(ServerLists.isDefault('wss://custom.example.com', RelayDefaults.inbox), isFalse);
    });
  });
}
