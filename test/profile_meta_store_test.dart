import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:chatme/services/profile_meta_store.dart';

void main() {
  const pubkey = 'profile-meta-test';
  const otherPubkey = 'profile-meta-other';

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_meta_store_test');
  });

  setUp(() async {
    Hive.init(tempDir.path);
    final box = await Hive.openBox('profile_meta');
    await box.clear();
    ProfileMetaStore.resetForTest();
  });

  tearDown(() async {
    await ProfileMetaStore.stopWatchingContactDeletions();
    ProfileMetaStore.resetForTest();
    await Hive.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('accepts a newer kind 0 and rejects an older one', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');

    expect(ProfileMetaStore.hasProfile(pubkey), isTrue);
    expect(ProfileMetaStore.shouldAccept(pubkey, 101, 'id101'), isTrue);
    expect(ProfileMetaStore.shouldAccept(pubkey, 99, 'id99'), isFalse);
  });

  test('rejects a replay of the same event id', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');

    expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'id100'), isFalse);
  });

  test('same timestamp keeps the lowest event id', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'bbb');

    expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'ccc'), isFalse);
    expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'aaa'), isTrue);

    await ProfileMetaStore.remember(pubkey, 100, 'aaa');
    expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'bbb'), isFalse);
  });

  test('a pubkey has no profile until a kind 0 is remembered', () async {
    expect(ProfileMetaStore.hasProfile(pubkey), isFalse);

    await ProfileMetaStore.remember(pubkey, 1, 'id1');
    expect(ProfileMetaStore.hasProfile(pubkey), isTrue);
  });

  test('a bare older kind 0 cannot clear a newer profile', () async {
    await ProfileMetaStore.remember(pubkey, 200, 'id200');

    expect(ProfileMetaStore.shouldAccept(pubkey, 150, 'id150'), isFalse);
    expect(ProfileMetaStore.hasProfile(pubkey), isTrue);
  });

  test('isCurrent follows the winning event', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');
    expect(ProfileMetaStore.isCurrent(pubkey, 100, 'id100'), isTrue);

    await ProfileMetaStore.remember(pubkey, 101, 'id101');
    expect(ProfileMetaStore.isCurrent(pubkey, 100, 'id100'), isFalse);
    expect(ProfileMetaStore.isCurrent(pubkey, 101, 'id101'), isTrue);
  });

  test('forget lets the same event be accepted again', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');
    expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'id100'), isFalse);

    await ProfileMetaStore.forget(pubkey);

    expect(ProfileMetaStore.hasProfile(pubkey), isFalse);
    expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'id100'), isTrue);
  });

  test('forget on an unknown pubkey does not throw', () async {
    await expectLater(ProfileMetaStore.forget('never-seen'), completes);
  });

  test('forget leaves other pubkeys alone', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');
    await ProfileMetaStore.remember(otherPubkey, 200, 'id200');

    await ProfileMetaStore.forget(pubkey);

    expect(ProfileMetaStore.hasProfile(pubkey), isFalse);
    expect(ProfileMetaStore.hasProfile(otherPubkey), isTrue);
    expect(ProfileMetaStore.isCurrent(otherPubkey, 200, 'id200'), isTrue);
  });

  test('forget is persisted across a restart', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');

    ProfileMetaStore.resetForTest();
    expect(ProfileMetaStore.hasProfile(pubkey), isTrue);

    await ProfileMetaStore.forget(pubkey);

    ProfileMetaStore.resetForTest();
    expect(ProfileMetaStore.hasProfile(pubkey), isFalse);
  });

  group('about', () {
    test('stores the bio of a kind 0 and exposes it', () async {
      await ProfileMetaStore.remember(pubkey, 100, 'id100', about: 'hello');

      expect(ProfileMetaStore.aboutFor(pubkey), 'hello');
    });

    test('is empty for a pubkey with no kind 0', () {
      expect(ProfileMetaStore.aboutFor('never-seen'), '');
    });

    test('a newer kind 0 replaces the bio, even with an empty one', () async {
      await ProfileMetaStore.remember(pubkey, 100, 'id100', about: 'first');
      await ProfileMetaStore.remember(pubkey, 101, 'id101', about: '');

      expect(ProfileMetaStore.aboutFor(pubkey), '');
    });

    test('omitting about keeps the previous bio', () async {
      await ProfileMetaStore.remember(pubkey, 100, 'id100', about: 'keep me');

      await ProfileMetaStore.remember(pubkey, 101, 'id101');

      expect(ProfileMetaStore.aboutFor(pubkey), 'keep me');
    });

    test('survives a restart', () async {
      await ProfileMetaStore.remember(pubkey, 100, 'id100', about: 'persisted');

      ProfileMetaStore.resetForTest();

      expect(ProfileMetaStore.aboutFor(pubkey), 'persisted');
    });

    test('forget clears the bio too', () async {
      await ProfileMetaStore.remember(pubkey, 100, 'id100', about: 'gone');

      await ProfileMetaStore.forget(pubkey);

      expect(ProfileMetaStore.aboutFor(pubkey), '');
    });

    test('needsAboutBackfill only for the current event with an unknown bio',
        () async {
      await ProfileMetaStore.remember(pubkey, 100, 'id100');

      expect(ProfileMetaStore.needsAboutBackfill(pubkey, 100, 'id100'), isTrue);
      expect(ProfileMetaStore.needsAboutBackfill(pubkey, 99, 'id100'), isFalse);
      expect(ProfileMetaStore.needsAboutBackfill(pubkey, 101, 'id101'), isFalse);

      await ProfileMetaStore.remember(pubkey, 100, 'id100', about: '');

      expect(
        ProfileMetaStore.needsAboutBackfill(pubkey, 100, 'id100'),
        isFalse,
      );
    });

    test('an older event cannot replace the current bio', () async {
      await ProfileMetaStore.remember(pubkey, 200, 'id200', about: 'new');

      expect(ProfileMetaStore.shouldAccept(pubkey, 100, 'id100'), isFalse);
      expect(ProfileMetaStore.aboutFor(pubkey), 'new');
    });
  });

  test('deleting a contacts row forgets only that pubkey', () async {
    await ProfileMetaStore.remember(pubkey, 100, 'id100');
    await ProfileMetaStore.remember(otherPubkey, 200, 'id200');

    final contacts = await Hive.openBox('contacts');
    ProfileMetaStore.watchContactDeletions(contacts);

    await contacts.put(pubkey, 'row');
    await contacts.put(otherPubkey, 'row');
    await contacts.delete(pubkey);
    await pumpEventQueue();

    expect(ProfileMetaStore.hasProfile(pubkey), isFalse);
    expect(ProfileMetaStore.hasProfile(otherPubkey), isTrue);
  });
}
