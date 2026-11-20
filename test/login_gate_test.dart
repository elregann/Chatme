import 'dart:io';

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

  test('createIdentity persists a keypair without opening the sync gate',
      () async {
    await AppSettings.instance.load();
    expect(AppSettings.instance.hasIdentity, isFalse);

    await AppSettings.instance.createIdentity();

    expect(AppSettings.instance.hasIdentity, isTrue);
    expect(AppSettings.instance.myMnemonic.split(' '), hasLength(12));
    expect(Hive.box('settings').get('my_pubkey'),
        AppSettings.instance.myPubkey);
    expect(Hive.box('settings').get('my_privkey'),
        AppSettings.instance.myPrivkey);
    expect(SyncGate.isActive, isFalse);
  });
}
