// import_account_atomic_test.dart

import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/models/contact.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const originalPrivkey =
      '1111111111111111111111111111111111111111111111111111111111111111';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('import_account_atomic');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ContactAdapter());
    await Hive.openBox('settings');
    await Hive.openBox<Contact>('contacts');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    final settings = Hive.box('settings');
    await settings.putAll({
      'my_privkey': originalPrivkey,
      'my_pubkey': bip340.getPublicKey(originalPrivkey),
      'my_mnemonic': '',
      'my_nip05': '',
      'is_nip05_verified': false,
      'my_about': '',
      'my_photo_url': '',
      'my_photo_path': '',
    });
    await AppSettings.instance.load();
  });

  test('a failed import keeps the in-memory identity unchanged', () async {
    const invalidPrivkey =
        '0000000000000000000000000000000000000000000000000000000000000000';

    await expectLater(
      AppSettings.instance.importAccount(invalidPrivkey),
      throwsA(isNotNull),
    );

    expect(AppSettings.instance.myPrivkey, originalPrivkey);
    expect(AppSettings.instance.myPubkey, bip340.getPublicKey(originalPrivkey));
    expect(Hive.box('settings').get('my_privkey'), originalPrivkey);
  });

  test('a valid import still switches the identity', () async {
    const nextPrivkey =
        '2222222222222222222222222222222222222222222222222222222222222222';

    await AppSettings.instance.importAccount(nextPrivkey);

    expect(AppSettings.instance.myPrivkey, nextPrivkey);
    expect(AppSettings.instance.myPubkey, bip340.getPublicKey(nextPrivkey));
    expect(Hive.box('settings').get('my_privkey'), nextPrivkey);
  });
}
