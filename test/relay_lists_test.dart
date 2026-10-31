// relay_lists_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/services/server_lists.dart';

void main() {
  group('RelayLists.fromStored', () {
    test('nothing stored gives the defaults', () {
      final lists = RelayLists.fromStored(null, null);
      expect(lists.inbox, RelayDefaults.inbox);
      expect(lists.other, RelayDefaults.other);
    });

    test('data that is not a list gives the defaults', () {
      final lists = RelayLists.fromStored('abc', 5);
      expect(lists.inbox, RelayDefaults.inbox);
      expect(lists.other, RelayDefaults.other);
    });

    test('drops entries that are not usable and tidies the rest', () {
      final lists = RelayLists.fromStored(
        ['relay.one.example', 'WSS://relay.one.example/', 'ws://bad.example', 5, null, 'wss://nos.lol'],
        const [],
      );
      expect(lists.inbox, ['wss://relay.one.example', 'wss://nos.lol']);
    });

    test('an empty inbox list falls back to the default inbox', () {
      expect(RelayLists.fromStored(const [], null).inbox, RelayDefaults.inbox);
    });

    test('an inbox list with nothing usable falls back to the default inbox', () {
      expect(RelayLists.fromStored(['ws://a.example', 'localhost'], null).inbox, RelayDefaults.inbox);
    });

    test('an empty other list stays empty, the user chose that', () {
      expect(RelayLists.fromStored(null, const []).other, isEmpty);
    });

    test('a relay in the inbox is left out of the other list', () {
      final lists = RelayLists.fromStored(
        ['wss://a.example.com'],
        ['wss://a.example.com', 'wss://b.example.com'],
      );
      expect(lists.other, ['wss://b.example.com']);
    });

    test('lists longer than the limit are cut', () {
      final many = [for (var i = 0; i < 9; i++) 'wss://r$i.example.com'];
      final lists = RelayLists.fromStored(many, many.map((e) => e.replaceFirst('r', 'o')).toList());
      expect(lists.inbox, hasLength(ListLimits.inboxMax));
      expect(lists.other, hasLength(ListLimits.otherMax));
    });

    test('all is the inbox relays followed by the others', () {
      final lists = RelayLists.fromStored(['wss://a.example.com'], ['wss://b.example.com']);
      expect(lists.all, ['wss://a.example.com', 'wss://b.example.com']);
    });

    test('the defaults together are the five relays used so far', () {
      expect(RelayLists.defaults().all.toSet(), {
        'wss://nos.lol',
        'wss://auth.nostr1.com',
        'wss://messaging.coracle.social',
        'wss://relay.damus.io',
        'wss://relay.primal.net',
      });
    });
  });

  group('RelayDiff', () {
    test('lists what was added and what was removed', () {
      final diff = RelayDiff.between(
        ['wss://a.example.com', 'wss://b.example.com'],
        ['wss://b.example.com', 'wss://c.example.com'],
      );
      expect(diff.added, ['wss://c.example.com']);
      expect(diff.removed, ['wss://a.example.com']);
    });

    test('nothing changes when only the order differs', () {
      final diff = RelayDiff.between(
        ['wss://a.example.com', 'wss://b.example.com'],
        ['wss://b.example.com', 'wss://a.example.com'],
      );
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
      expect(diff.isEmpty, isTrue);
    });

    test('moving a relay between the two lists is not a change of connections', () {
      final before = RelayLists.fromStored(['wss://a.example.com'], ['wss://b.example.com']);
      final after = RelayLists.fromStored(['wss://a.example.com', 'wss://b.example.com'], const []);
      expect(RelayDiff.between(before.all, after.all).isEmpty, isTrue);
    });
  });
}
