// lib/services/identity_secret_store.dart
//
// Stores Nostr identity secrets (private key and BIP-39 mnemonic) in
// platform secure storage. Hive settings is not used for these secrets.
//
// The production implementation delegates to flutter_secure_storage
// (Keychain / Keystore). Tests can inject an in-memory implementation.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class IdentitySecretStore {
  Future<String?> readPrivkey();
  Future<String?> readMnemonic();
  Future<void> write({
    required String privkey,
    required String mnemonic,
  });
  Future<void> clear();
}

/// In-memory implementation for tests. Not persisted.
class InMemoryIdentitySecretStore implements IdentitySecretStore {
  String? _privkey;
  String? _mnemonic;

  @override
  Future<String?> readPrivkey() async => _privkey;

  @override
  Future<String?> readMnemonic() async => _mnemonic;

  @override
  Future<void> write({
    required String privkey,
    required String mnemonic,
  }) async {
    _privkey = privkey;
    _mnemonic = mnemonic;
  }

  @override
  Future<void> clear() async {
    _privkey = null;
    _mnemonic = null;
  }
}

class SecureIdentitySecretStore implements IdentitySecretStore {
  SecureIdentitySecretStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const String _privkeyKey = 'nostr_identity_privkey';
  static const String _mnemonicKey = 'nostr_identity_mnemonic';

  static IdentitySecretStore? _debugOverride;

  @visibleForTesting
  static void setDebugOverrideForTest(IdentitySecretStore? store) {
    _debugOverride = store;
  }

  final FlutterSecureStorage _storage;

  static IdentitySecretStore resolve() =>
      _debugOverride ?? SecureIdentitySecretStore();

  /// Reads privkey for background/notification isolates. Returns empty string
  /// on any failure so callers can fail closed without crashing the handler.
  static Future<String> readPrivkeySafe() async {
    try {
      return await resolve().readPrivkey() ?? '';
    } catch (e) {
      debugPrint('[IdentitySecretStore] readPrivkey failed | $e');
      return '';
    }
  }

  @override
  Future<String?> readPrivkey() {
    final d = _debugOverride;
    if (d != null && !identical(d, this)) return d.readPrivkey();
    return _storage.read(key: _privkeyKey);
  }

  @override
  Future<String?> readMnemonic() {
    final d = _debugOverride;
    if (d != null && !identical(d, this)) return d.readMnemonic();
    return _storage.read(key: _mnemonicKey);
  }

  @override
  Future<void> write({
    required String privkey,
    required String mnemonic,
  }) async {
    final d = _debugOverride;
    if (d != null && !identical(d, this)) {
      await d.write(privkey: privkey, mnemonic: mnemonic);
      return;
    }
    await _storage.write(key: _privkeyKey, value: privkey);
    await _storage.write(key: _mnemonicKey, value: mnemonic);
  }

  @override
  Future<void> clear() async {
    final d = _debugOverride;
    if (d != null && !identical(d, this)) {
      await d.clear();
      return;
    }
    await _storage.delete(key: _privkeyKey);
    await _storage.delete(key: _mnemonicKey);
  }
}
