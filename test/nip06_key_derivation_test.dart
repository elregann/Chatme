// nip06_key_derivation_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/crypto/key_generator.dart';

void main() {
  test('NIP-06 vector 1', () {
    expect(
      ChatMeVault.deriveNostrPrivateKey(
        'leader monkey parrot ring guide accident before fence cannon height naive bean',
      ),
      '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a',
    );
  });

  test('NIP-06 vector 2', () {
    expect(
      ChatMeVault.deriveNostrPrivateKey(
        'what bleak badge arrange retreat wolf trade produce cricket blur garlic valid proud rude strong choose busy staff weather area salt hollow arm fade',
      ),
      'c15d739894c81a2fcfd3a2df85a0d2c0dbc47a280d092799f144d73d7ae78add',
    );
  });

  test('same phrase always gives the same key, spacing and case ignored', () {
    final a = ChatMeVault.deriveNostrPrivateKey(ChatMeVault.generateNewMnemonic());
    final m = ChatMeVault.generateNewMnemonic();
    expect(
      ChatMeVault.deriveNostrPrivateKey(m),
      ChatMeVault.deriveNostrPrivateKey('  ${m.toUpperCase().replaceAll(' ', '  ')} '),
    );
    expect(a.length, 64);
  });

  test('invalid phrase throws', () {
    expect(() => ChatMeVault.deriveNostrPrivateKey('not a real phrase at all'), throwsA(isA<String>()));
  });
}
