// contact_model_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/core/utils/key_utils.dart';

void main() {
  const pubkey = '7e7e9c42a91bfef19fa929e59fda7b3c4ba0d1c8f7c4c2f0e1d5b6a7c8d9e0f1';

  Contact buildContact({String name = '', String? globalId}) => Contact(
        pubkey: pubkey,
        name: name,
        globalId: globalId,
      );

  group('isPlaceholderName', () {
    test('empty string is a placeholder', () {
      expect(Contact.isPlaceholderName('', pubkey), isTrue);
    });

    test('npub stub is a placeholder', () {
      expect(Contact.isPlaceholderName('npub1xyz123abc', pubkey), isTrue);
    });

    test('shortened npub stub (as published by old broadcasts) is a placeholder', () {
      expect(Contact.isPlaceholderName('npub1xyz...abc', pubkey), isTrue);
    });

    test('"User " stub is a placeholder', () {
      expect(Contact.isPlaceholderName('User 123', pubkey), isTrue);
    });

    test('raw pubkey is a placeholder', () {
      expect(Contact.isPlaceholderName(pubkey, pubkey), isTrue);
    });

    test('a real handle is not a placeholder', () {
      expect(Contact.isPlaceholderName('ismael', pubkey), isFalse);
    });

    test('a real handle of a different user is not a placeholder', () {
      expect(Contact.isPlaceholderName(pubkey, 'a' * 64), isFalse);
    });
  });

  group('displayName', () {
    test('falls back to formatted pubkey for an empty name', () {
      final contact = buildContact(name: '');
      expect(contact.displayName, KeyUtils.formatDisplayName(pubkey));
    });

    test('falls back to formatted pubkey for an npub stub name', () {
      final contact = buildContact(name: 'npub1abcdefgh');
      expect(contact.displayName, KeyUtils.formatDisplayName(pubkey));
    });

    test('falls back to formatted pubkey for a "User " stub name', () {
      final contact = buildContact(name: 'User 42');
      expect(contact.displayName, KeyUtils.formatDisplayName(pubkey));
    });

    test('falls back to formatted pubkey when the name equals the pubkey', () {
      final contact = buildContact(name: pubkey);
      expect(contact.displayName, KeyUtils.formatDisplayName(pubkey));
    });

    test('shows a real nickname as-is', () {
      final contact = buildContact(name: 'ward');
      expect(contact.displayName, 'ward');
    });
  });

  group('globalHandle / hasGlobalId', () {
    test('is empty when globalId is null', () {
      final contact = buildContact();
      expect(contact.globalHandle, '');
      expect(contact.hasGlobalId, isFalse);
    });

    test('exposes the claimed handle', () {
      final contact = buildContact(globalId: 'edwards');
      expect(contact.globalHandle, 'edwards');
      expect(contact.hasGlobalId, isTrue);
    });

    test('reports raw values as-is — placeholder detection is isPlaceholderName\'s job', () {
      final contact = buildContact(globalId: 'npub1xyz...abc');
      expect(contact.globalHandle, 'npub1xyz...abc');
      expect(contact.hasGlobalId, isTrue);
    });
  });
}
