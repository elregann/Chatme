import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:chatme/core/crypto/key_generator.dart';
import 'package:chatme/models/contact.dart';
import 'package:chatme/services/app_settings.dart';
import 'package:chatme/services/identity_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InMemoryIdentitySecretStore secretStore;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('identity_secret_storage');
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
    secretStore = InMemoryIdentitySecretStore();
    AppSettings.instance.setIdentitySecretStoreForTest(secretStore);
    await Hive.box('settings').clear();
    await Hive.box<Contact>('contacts').clear();
    AppSettings.instance.myPubkey = '';
    AppSettings.instance.myPrivkey = '';
    AppSettings.instance.myMnemonic = '';
    AppSettings.instance.identitySecretsUnavailable = false;
  });

  test('load migrates legacy hive secrets to secure storage and removes them',
      () async {
    const privkey =
        '1111111111111111111111111111111111111111111111111111111111111111';
    final pubkey = bip340.getPublicKey(privkey);
    await Hive.box('settings').putAll({
      'my_privkey': privkey,
      'my_mnemonic': 'legacy words',
      'my_pubkey': pubkey,
    });

    await AppSettings.instance.load();

    expect(AppSettings.instance.myPrivkey, privkey);
    expect(AppSettings.instance.myMnemonic, 'legacy words');
    expect(await secretStore.readPrivkey(), privkey);
    expect(await secretStore.readMnemonic(), 'legacy words');
    expect(Hive.box('settings').get('my_privkey'), isNull);
    expect(Hive.box('settings').get('my_mnemonic'), isNull);
    expect(Hive.box('settings').get('my_pubkey'), pubkey);
  });

  test('load prefers secure storage over legacy hive secrets', () async {
    const securePrivkey =
        '2222222222222222222222222222222222222222222222222222222222222222';
    const legacyPrivkey =
        '3333333333333333333333333333333333333333333333333333333333333333';
    await secretStore.write(privkey: securePrivkey, mnemonic: 'secure words');
    await Hive.box('settings').putAll({
      'my_privkey': legacyPrivkey,
      'my_mnemonic': 'legacy words',
      'my_pubkey': bip340.getPublicKey(legacyPrivkey),
    });

    await AppSettings.instance.load();

    expect(AppSettings.instance.myPrivkey, securePrivkey);
    expect(AppSettings.instance.myMnemonic, 'secure words');
    expect(Hive.box('settings').get('my_privkey'), isNull);
    expect(Hive.box('settings').get('my_mnemonic'), isNull);
  });

  test('createIdentity stores secrets in secure storage, not hive', () async {
    await AppSettings.instance.load();
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final expectedPrivkey = ChatMeVault.deriveNostrPrivateKey(mnemonic);
    final expectedPubkey = bip340.getPublicKey(expectedPrivkey);

    await AppSettings.instance.createIdentity(mnemonic);

    expect(await secretStore.readPrivkey(), expectedPrivkey);
    expect(await secretStore.readMnemonic(), mnemonic);
    expect(Hive.box('settings').get('my_privkey'), isNull);
    expect(Hive.box('settings').get('my_mnemonic'), isNull);
    expect(Hive.box('settings').get('my_pubkey'), expectedPubkey);
  });

  test('importAccount stores secrets in secure storage, not hive', () async {
    await AppSettings.instance.load();
    const nextPrivkey =
        '2222222222222222222222222222222222222222222222222222222222222222';

    await AppSettings.instance.importAccount(nextPrivkey);

    expect(await secretStore.readPrivkey(), nextPrivkey);
    expect(await secretStore.readMnemonic(), '');
    expect(Hive.box('settings').get('my_privkey'), isNull);
    expect(Hive.box('settings').get('my_mnemonic'), isNull);
    expect(AppSettings.instance.myPrivkey, nextPrivkey);
  });

  test('load marks identity secrets unavailable when secure read fails and no legacy exists',
      () async {
    AppSettings.instance.setIdentitySecretStoreForTest(_ThrowingReadSecretStore());
    await Hive.box('settings').putAll({
      'my_pubkey': 'stale_pubkey',
    });

    await AppSettings.instance.load();

    expect(AppSettings.instance.identitySecretsUnavailable, isTrue);
    expect(AppSettings.instance.myPrivkey, isEmpty);
    expect(AppSettings.instance.myMnemonic, isEmpty);
    expect(AppSettings.instance.myPubkey, 'stale_pubkey');
  });

  test('createIdentity is blocked when identity secrets are unavailable',
      () async {
    AppSettings.instance.setIdentitySecretStoreForTest(_ThrowingReadSecretStore());
    await AppSettings.instance.load();

    await expectLater(
      AppSettings.instance.createIdentity(
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('clearIdentitySecrets throws when secrets still remain after clear',
      () async {
    final store = _UndeletableSecretStore();
    AppSettings.instance.setIdentitySecretStoreForTest(store);
    await store.write(privkey: '1111', mnemonic: 'words');

    await expectLater(
      AppSettings.instance.clearIdentitySecrets(),
      throwsA(isA<StateError>()),
    );
  });

  test('readPrivkeySafe returns empty when secure read throws', () async {
    SecureIdentitySecretStore.setDebugOverrideForTest(_ThrowingReadSecretStore());

    final privkey = await SecureIdentitySecretStore.readPrivkeySafe();

    expect(privkey, isEmpty);
  });
}

class _ThrowingReadSecretStore implements IdentitySecretStore {
  @override
  Future<void> clear() async {}

  @override
  Future<String?> readMnemonic() async => throw Exception('keystore read failed');

  @override
  Future<String?> readPrivkey() async => throw Exception('keystore read failed');

  @override
  Future<void> write({required String privkey, required String mnemonic}) async {}
}

class _UndeletableSecretStore implements IdentitySecretStore {
  String? _privkey;
  String? _mnemonic;

  @override
  Future<void> clear() async {}

  @override
  Future<String?> readMnemonic() async => _mnemonic;

  @override
  Future<String?> readPrivkey() async => _privkey;

  @override
  Future<void> write({required String privkey, required String mnemonic}) async {
    _privkey = privkey;
    _mnemonic = mnemonic;
  }
}
