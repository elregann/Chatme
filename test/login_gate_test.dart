import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/crypto/key_generator.dart';
import 'package:chatme/core/utils/sync_gate.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('chatme_login_gate_test');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    SyncGate.resetForTest();
    await Hive.box('settings').clear();
    AppSettings.instance.myPubkey = '';
    AppSettings.instance.myPrivkey = '';
    AppSettings.instance.myMnemonic = '';
  });

  test('first launch stays signed out until the user creates or restores an account',
      () async {
    await AppSettings.instance.load();

    expect(AppSettings.instance.myPubkey, isEmpty);
    expect(AppSettings.instance.myPrivkey, isEmpty);
    expect(AppSettings.instance.myMnemonic, isEmpty);
    expect(Hive.box('settings').get('my_pubkey'), isNull);
    expect(Hive.box('settings').get('my_privkey'), isNull);
    expect(SyncGate.isActive, isFalse);
  });

  test('createIdentity persists the given phrase without opening the sync gate',
      () async {
    await AppSettings.instance.load();
    expect(AppSettings.instance.hasIdentity, isFalse);

    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    await AppSettings.instance.createIdentity(mnemonic);

    final expectedPrivkey = ChatMeVault.deriveNostrPrivateKey(mnemonic);

    expect(AppSettings.instance.hasIdentity, isTrue);
    expect(AppSettings.instance.myMnemonic, mnemonic);
    expect(AppSettings.instance.myPrivkey, expectedPrivkey);
    expect(AppSettings.instance.myPubkey, bip340.getPublicKey(expectedPrivkey));
    expect(Hive.box('settings').get('my_mnemonic'), mnemonic);
    expect(Hive.box('settings').get('my_privkey'), expectedPrivkey);
    expect(Hive.box('settings').get('my_pubkey'),
        AppSettings.instance.myPubkey);
    expect(SyncGate.isActive, isFalse);
  });
}
