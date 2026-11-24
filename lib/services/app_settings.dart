// app_settings.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/crypto/key_generator.dart';
import '../core/utils/bio_text.dart';
import '../core/utils/shortcut_helper.dart';
import '../core/utils/debug_logger.dart';
import '../core/utils/key_utils.dart';
import '../models/contact.dart';
import 'identity_secret_store.dart';
import 'server_lists.dart';

class AppSettings {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  static AppSettings get instance => _instance;

  IdentitySecretStore _identitySecretStore = SecureIdentitySecretStore();

  @visibleForTesting
  void setIdentitySecretStoreForTest(IdentitySecretStore store) {
    _identitySecretStore = store;
    // ignore: invalid_use_of_visible_for_testing_member
    SecureIdentitySecretStore.setDebugOverrideForTest(store);
  }

  /// True only after WelcomePage has created or restored an identity.
  /// Signed-out devices have an empty keypair and must not connect or sync.
  bool get hasIdentity => myPubkey.isNotEmpty && myPrivkey.isNotEmpty;

  /// Set when secure secret storage could not be read. In that state we must
  /// not create/import an identity because an existing secret may be present but
  /// unreadable, and overwriting it would lock the user out.
  bool identitySecretsUnavailable = false;

  bool isNip05Verified = false;
  String myPubkey = '';
  String myPrivkey = '';
  String myMnemonic = '';
  String myNip05 = '';
  String myAbout = '';
  String myPhotoPath = '';
  String myPhotoUrl = '';

  /// Always derived, never stored: a stored copy goes stale when a global ID
  /// is released or when an account is restored.
  String get myName {
    if (myNip05.isNotEmpty) return myNip05.split('@').first;
    return myPubkey.isEmpty ? '' : formatDisplayName(myPubkey);
  }

  bool linkPreviewsEnabled = false;
  bool readReceiptsEnabled = true;

  /// Copies received photos to the Chatme album of the gallery.
  bool saveToGalleryEnabled = false;

  /// Relays where others deliver messages to us (announced as kind 10050).
  List<String> inboxRelays = List.of(RelayDefaults.inbox);

  /// Extra relays Chatme also connects to.
  List<String> otherRelays = List.of(RelayDefaults.other);

  /// Relays used for NIP-50 profile search. They are only connected while a
  /// search runs, never kept open with the message relays.
  List<String> searchRelays = List.of(RelayDefaults.search);

  /// File servers (Blossom) for uploads, tried from top to bottom.
  List<String> blossomServers = List.of(BlossomDefaults.servers);

  /// Bumped when the file server list changes, for screens that show it.
  final ValueNotifier<int> blossomVersion = ValueNotifier(0);

  /// Every relay Chatme connects to, inbox relays first.
  List<String> get allRelays => [...inboxRelays, ...otherRelays];

  Future<void> load() async {
    try {
      final settingsBox = Hive.box('settings');

      // Load persisted values
      myPubkey = settingsBox.get('my_pubkey', defaultValue: '');
      final legacyPrivkey =
          settingsBox.get('my_privkey', defaultValue: '') as String;
      final legacyMnemonic =
          settingsBox.get('my_mnemonic', defaultValue: '') as String;
      await _loadIdentitySecrets(
        settingsBox,
        legacyPrivkey: legacyPrivkey,
        legacyMnemonic: legacyMnemonic,
      );
      myNip05 = settingsBox.get('my_nip05', defaultValue: '');
      myPhotoPath = settingsBox.get('my_photo_path', defaultValue: '');
      myPhotoUrl = settingsBox.get('my_photo_url', defaultValue: '');
      isNip05Verified =
          settingsBox.get('is_nip05_verified', defaultValue: false);
      myAbout = settingsBox.get('my_about', defaultValue: '');

      // No identity is created here. A signed-out device stays signed out
      // until WelcomePage creates or restores one; that flow owns the sync
      // gate and the relay connection.

      linkPreviewsEnabled = settingsBox.get('link_previews_enabled', defaultValue: false);
      readReceiptsEnabled = settingsBox.get('read_receipts_enabled', defaultValue: true);
      saveToGalleryEnabled = settingsBox.get('save_to_gallery', defaultValue: false);

      final relayLists = RelayLists.fromStored(
        settingsBox.get('relays_inbox'),
        settingsBox.get('relays_other'),
        settingsBox.get('relays_search'),
      );
      inboxRelays = relayLists.inbox;
      otherRelays = relayLists.other;
      searchRelays = relayLists.search;

      blossomServers = BlossomLists.fromStored(settingsBox.get('blossom_servers'));

      final pubkeyLabel = myPubkey.isEmpty
          ? 'none'
          : '${myPubkey.substring(0, myPubkey.length < 16 ? myPubkey.length : 16)}...';
      DebugLogger.log('[Settings] Loaded. Pubkey: $pubkeyLabel', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('[Settings] Load failed | $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> setLinkPreviewsEnabled(bool value) async {
    linkPreviewsEnabled = value;
    final settingsBox = Hive.box('settings');
    await settingsBox.put('link_previews_enabled', value);
  }

  Future<void> setRelayLists({
    required List<String> inbox,
    required List<String> other,
    required List<String> search,
  }) async {
    inboxRelays = List.of(inbox);
    otherRelays = List.of(other);
    searchRelays = List.of(search);
    final settingsBox = Hive.box('settings');
    await settingsBox.put('relays_inbox', inboxRelays);
    await settingsBox.put('relays_other', otherRelays);
    await settingsBox.put('relays_search', searchRelays);
  }

  Future<void> setBlossomServers(List<String> servers) async {
    blossomServers = List.of(servers);
    final settingsBox = Hive.box('settings');
    await settingsBox.put('blossom_servers', blossomServers);
    blossomVersion.value++;
  }

  Future<void> setSaveToGalleryEnabled(bool value) async {
    saveToGalleryEnabled = value;
    final settingsBox = Hive.box('settings');
    await settingsBox.put('save_to_gallery', value);
  }

  Future<void> setReadReceiptsEnabled(bool value) async {
    readReceiptsEnabled = value;
    final settingsBox = Hive.box('settings');
    await settingsBox.put('read_receipts_enabled', value);
  }

  Future<String?> fetchGlobalUsername(String pubkey) async {
    return _fetchNameFromFirebase(pubkey);
  }

  /// Looks a pubkey up in the Chatme directory (`users/<pubkey>`).
  ///
  /// A missing row and a failed request are deliberately different results:
  /// only a definitive "not registered" may clear a cached handle. A timeout
  /// or offline device must never make a valid `name@chatme` disappear.
  static Future<DirectoryIdentityLookup> lookupDirectoryIdentity(
      String pubkey) async {
    if (pubkey.isEmpty) return const DirectoryIdentityLookup.notFound();

    try {
      const String rtdbUrl =
          "https://chatme-412d1-default-rtdb.asia-southeast1.firebasedatabase.app";
      final db =
          FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: rtdbUrl);
      final snapshot = await db
          .ref("users/$pubkey")
          .get()
          .timeout(const Duration(seconds: 10));
      if (!snapshot.exists) return const DirectoryIdentityLookup.notFound();

      final value = snapshot.value;
      final name = value is String ? value.trim() : '';
      if (name.isEmpty) return const DirectoryIdentityLookup.notFound();
      return DirectoryIdentityLookup.found(name);
    } catch (e) {
      DebugLogger.log('[Settings] Fetch name from Firebase failed | $e',
          type: 'ERROR');
      return const DirectoryIdentityLookup.failed();
    }
  }

  Future<String?> _fetchNameFromFirebase(String pubkey) async {
    final result = await lookupDirectoryIdentity(pubkey);
    return result.isFound ? result.name : null;
  }

  /// Creates an identity from the exact phrase shown on CreateAccountPage.
  ///
  /// The phrase is passed in, never regenerated here: the user must be able
  /// to restore the same pubkey with the words they just wrote down.
  /// The caller owns the sync gate and relay connection.
  Future<void> createIdentity(String mnemonic) async {
    _ensureIdentitySecretsAvailable();
    final privateKey = ChatMeVault.deriveNostrPrivateKey(mnemonic);
    final publicKey = bip340.getPublicKey(privateKey);

    final previousPrivkey = await _identitySecretStore.readPrivkey();
    final previousMnemonic = await _identitySecretStore.readMnemonic();
    await _identitySecretStore.write(
      privkey: privateKey,
      mnemonic: mnemonic,
    );

    try {
      myMnemonic = mnemonic;
      myPrivkey = privateKey;
      myPubkey = publicKey;
      myNip05 = '';
      myAbout = '';
      myPhotoPath = '';
      myPhotoUrl = '';
      isNip05Verified = false;

      await Hive.box('settings').putAll({
        'my_pubkey': publicKey,
        'my_nip05': '',
        'is_nip05_verified': false,
        'my_about': '',
        'my_photo_url': '',
        'my_photo_path': '',
      });
      await _removeLegacyIdentitySecrets(Hive.box('settings'), compact: true);
    } catch (e) {
      await _restoreIdentitySecrets(previousPrivkey, previousMnemonic);
      rethrow;
    }

    DebugLogger.log(
      '[Settings] New identity created: ${publicKey.substring(0, 16)}...',
      type: 'SETUP',
    );
  }

  Future<void> importAccount(String input) async {
    _ensureIdentitySecretsAvailable();
    try {
      final settingsBox = Hive.box('settings');
      final cleaned = input.trim().split(RegExp(r'\s+')).join(' ');

      final String privkey;
      final String mnemonic;
      if (cleaned.startsWith('nsec')) {
        privkey = KeyUtils.fromNsec(cleaned);
        mnemonic = '';
      } else if (cleaned.split(' ').length >= 12) {
        privkey = ChatMeVault.deriveNostrPrivateKey(cleaned);
        mnemonic = cleaned;
      } else if (cleaned.length == 64) {
        privkey = cleaned;
        mnemonic = '';
      } else {
        throw 'Invalid input format. Use nsec, 64-char hex, or 12 words.';
      }

      if (privkey.length != 64) {
        throw 'Invalid private key format.';
      }

      final pubkey = bip340.getPublicKey(privkey);

      // Try to fetch existing display name from Firebase
      final fetchedName = await _fetchNameFromFirebase(pubkey);
      final nip05 = fetchedName != null ? '$fetchedName@chatme' : '';
      final nip05Verified = fetchedName != null;

      // Keep every fallback in local variables until the write succeeds. A
      // failure above must not leave the in-memory key on a different account
      // than the key persisted on disk.
      final previousPrivkey = await _identitySecretStore.readPrivkey();
      final previousMnemonic = await _identitySecretStore.readMnemonic();
      await _identitySecretStore.write(
        privkey: privkey,
        mnemonic: mnemonic,
      );
      try {
        await settingsBox.putAll({
          'my_pubkey': pubkey,
          'my_nip05': nip05,
          'is_nip05_verified': nip05Verified,
          'my_about': '',
          'my_photo_url': '',
          'my_photo_path': '',
        });
        await _removeLegacyIdentitySecrets(settingsBox, compact: true);

        myPubkey = pubkey;
        myPrivkey = privkey;
        myMnemonic = mnemonic;
        myNip05 = nip05;
        isNip05Verified = nip05Verified;
        // Reset identity-specific state so a different account doesn't inherit
        // the previous account's photo. It is re-populated once the relay
        // delivers the account's kind-0 event.
        myAbout = '';
        myPhotoUrl = '';
        myPhotoPath = '';
      } catch (e) {
        await _restoreIdentitySecrets(previousPrivkey, previousMnemonic);
        rethrow;
      }

      // The restored account may already have a contact row from an older
      // session. Its handle comes from the directory, never from a kind 0.
      await syncOwnContactIdentity();

      DebugLogger.log('[Settings] Account restored: $myPubkey', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('[Settings] Import account failed | $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> savePhotoPath(String path) async {
    if (myPhotoPath == path) return;
    myPhotoPath = path;
    await Hive.box('settings').put('my_photo_path', path);
  }

  Future<void> savePhotoUrl(String url) async {
    if (myPhotoUrl == url) return;
    myPhotoUrl = url;
    await Hive.box('settings').put('my_photo_url', url);
  }

  /// Saves the user's bio, normalized and limited to [BioText.maxUserLength].
  ///
  /// Only local storage changes here; the caller republishes kind 0 when it
  /// wants the new bio to reach relays. A no-op when nothing changed keeps
  /// the Me tab from rebuilding on repeated saves.
  Future<void> setMyAbout(String about) async {
    final cleaned = BioText.sanitize(about, maxLength: BioText.maxUserLength);
    if (cleaned == myAbout) return;
    myAbout = cleaned;
    await Hive.box('settings').put('my_about', cleaned);
  }

  Future<void> loadPhotoPath() async {
    myPhotoPath = Hive.box('settings').get('my_photo_path', defaultValue: '');
  }

  Future<void> updateNip05(String newNip05, bool verified) async {
    final nip05Changed = myNip05 != newNip05;
    final verifiedChanged = isNip05Verified != verified;
    if (!nip05Changed && !verifiedChanged) return;

    myNip05 = newNip05;
    isNip05Verified = verified;
    final settingsBox = Hive.box('settings');
    if (nip05Changed) {
      await settingsBox.put('my_nip05', newNip05);
    }
    if (verifiedChanged) {
      await settingsBox.put('is_nip05_verified', verified);
    }
    await syncOwnContactIdentity();
    DebugLogger.log('[Settings] Identity updated: $newNip05 (verified: $verified)', type: 'SETUP');
  }

  Future<Map<String, dynamic>> backupKeys() async {
    try {
      final backupData = {
        'public_key': myPubkey,
        'private_key': myPrivkey,
        'name': myName,
        'backup_date': DateTime.now().toIso8601String(),
        'app': 'Chatme',
        'version': '1.0.0',
      };

      final backupString = jsonEncode(backupData);
      await Clipboard.setData(ClipboardData(text: backupString));
      DebugLogger.log('[Settings] Keys copied to clipboard', type: 'SETUP');
      return backupData;
    } catch (e) {
      DebugLogger.log('[Settings] Backup keys failed | $e', type: 'ERROR');
      rethrow;
    }
  }

  String exportKeys() {
    return '''
CHATME KEY BACKUP
IMPORTANT: Save this information in a secure place.
Public Key: $myPubkey
Private Key: $myPrivkey
Name: $myName
Backup Date: ${DateTime.now().toString()}
''';
  }

  static String getContactDisplayName(Contact contact) {
    return contact.displayName;
  }

  /// Confirms a contact against the Chatme directory once.
  ///
  /// Directory confirmation is the only way a row earns a
  /// `name@chatme` handle. A kind-0 profile no longer prerequires (or blocks)
  /// this check: it runs for every contact, even one whose metadata already
  /// arrived. Only a successful request sets the hydration flag, so a
  /// temporary network failure retries on the next call instead of leaving
  /// the contact unconfirmed for good.
  static Future<void> hydrateSingleContact(
    String pubkey, {
    bool force = false,
  }) async {
    if (pubkey.isEmpty) return;
    // Our own identity is local state (`myNip05`), not a directory lookup.
    if (pubkey == AppSettings.instance.myPubkey) return;

    final settingsBox = Hive.box('settings');
    final flagKey = 'hydrated_$pubkey';
    if (!force && settingsBox.get(flagKey, defaultValue: false) == true) {
      return;
    }

    final result = await lookupDirectoryIdentity(pubkey);
    if (!result.isDefinitive) {
      // Network failure: keep the old row and leave the flag unset.
      return;
    }

    try {
      if (result.isFound) {
        await _applyDirectoryIdentityToContact(
          pubkey,
          result.name,
          displayName: result.name,
        );
      } else {
        // The directory answered: the pubkey is not registered. Only this
        // definitive answer may clear a cached handle.
        await _applyDirectoryIdentityToContact(pubkey, null);
      }
      await settingsBox.put(flagKey, true);
    } catch (e) {
      DebugLogger.log('[Settings] Contact hydration failed | $e', type: 'ERROR');
    }
  }

  static Future<void> hydrateMissingContactNames() async {
    await _migrateContactGlobalIdsToDirectory();
    await _cleanupPlaceholderGlobalIds();
    final contactsBox = Hive.box<Contact>('contacts');
    for (final key in contactsBox.keys.toList()) {
      await hydrateSingleContact(key.toString());
    }
  }

  /// Applies the locally trusted directory handle to our own contact row.
  ///
  /// Claiming or releasing an ID used to depend on the kind-0 receiver
  /// copying `name` into `globalId`. Since only the directory may set a
  /// handle now, the row is updated here from [myNip05] instead.
  static Future<void> syncOwnContactIdentity() async {
    final settings = AppSettings.instance;
    if (settings.myPubkey.isEmpty) return;
    final handle = settings.myNip05.isNotEmpty
        ? settings.myNip05.split('@').first.trim()
        : null;
    await _applyDirectoryIdentityToContact(settings.myPubkey, handle);
  }

  /// Writes a directory result to a contact row.
  ///
  /// [handle] is the confirmed username, or null for a confirmed "not
  /// registered". A saved nickname is never replaced; only an unsaved row
  /// follows the directory name.
  static Future<void> _applyDirectoryIdentityToContact(
    String pubkey,
    String? handle, {
    String? displayName,
  }) async {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final contact = contactsBox.get(pubkey);
      if (contact == null) return;

      final normalized = (handle == null ||
              handle.isEmpty ||
              Contact.isPlaceholderName(handle, pubkey))
          ? null
          : handle;

      var changed = false;
      if (contact.globalId != normalized) {
        contact.globalId = normalized;
        changed = true;
      }
      if (displayName != null &&
          displayName.isNotEmpty &&
          !contact.isSaved &&
          contact.name != displayName) {
        contact.name = displayName;
        changed = true;
      }

      if (changed) {
        await contactsBox.put(pubkey, contact);
        await ShortcutHelper.pushConversationShortcut(
          id: pubkey,
          name: contact.displayName,
          avatarBytes: null,
        );
      }
    } catch (e) {
      DebugLogger.log('[Settings] Contact identity update failed | $e',
          type: 'ERROR');
    }
  }

  /// One-time migration for directory-confirmed identities.
  ///
  /// Earlier versions wrote `globalId` straight from a kind-0 `name`, which
  /// made any Nostr profile look like a Chatme username. Drop every cached
  /// handle and the per-contact hydration flags, then let
  /// [hydrateMissingContactNames] re-confirm each row with the directory.
  static Future<void> _migrateContactGlobalIdsToDirectory() async {
    final settingsBox = Hive.box('settings');
    const migrationKey = 'contact_global_id_directory_migration';
    if (settingsBox.get(migrationKey, defaultValue: false) == true) return;

    try {
      final contactsBox = Hive.box<Contact>('contacts');
      var cleared = 0;
      for (final key in contactsBox.keys.toList()) {
        final contact = contactsBox.get(key.toString());
        if (contact == null || contact.globalId == null) continue;
        contact.globalId = null;
        await contactsBox.put(key, contact);
        cleared++;
      }

      final flags = settingsBox.keys
          .where((k) => k.toString().startsWith('hydrated_'))
          .toList();
      if (flags.isNotEmpty) {
        await settingsBox.deleteAll(flags);
      }

      await settingsBox.put(migrationKey, true);
      DebugLogger.log(
        '[Settings] Directory identity migration done '
        '($cleared handles cleared, ${flags.length} contacts re-hydrating)',
        type: 'SETUP',
      );
    } catch (e) {
      DebugLogger.log('[Settings] Directory identity migration failed | $e',
          type: 'ERROR');
    }
  }

  /// One-time cleanup for placeholder values that leaked into `globalId`
  /// from kind-0 profiles published by older app versions while the user's
  /// global ID was disconnected (e.g. "npub1..." stubs). Only `globalId` is
  /// cleared — the local `name` is user-authored and is never touched.
  Future<void> _loadIdentitySecrets(
    Box settingsBox, {
    required String legacyPrivkey,
    required String legacyMnemonic,
  }) async {
    identitySecretsUnavailable = false;
    try {
      final securePrivkey = await _identitySecretStore.readPrivkey();
      final secureMnemonic = await _identitySecretStore.readMnemonic();
      final resolvedPrivkey = securePrivkey ?? '';
      final resolvedMnemonic = secureMnemonic ?? '';
      if (resolvedPrivkey.isNotEmpty) {
        myPrivkey = resolvedPrivkey;
        myMnemonic = resolvedMnemonic;
        await _removeLegacyIdentitySecrets(settingsBox, compact: true);
        return;
      }

      if (legacyPrivkey.isNotEmpty) {
        await _identitySecretStore.write(
          privkey: legacyPrivkey,
          mnemonic: legacyMnemonic,
        );
        final verifiedPrivkey = await _identitySecretStore.readPrivkey();
        final verifiedMnemonic = await _identitySecretStore.readMnemonic();
        if (verifiedPrivkey != legacyPrivkey ||
            verifiedMnemonic != legacyMnemonic) {
          throw StateError('secure identity readback mismatch');
        }
        myPrivkey = legacyPrivkey;
        myMnemonic = legacyMnemonic;
        await _removeLegacyIdentitySecrets(settingsBox, compact: true);
        return;
      }

      myPrivkey = '';
      myMnemonic = '';
      await _removeLegacyIdentitySecrets(settingsBox);
    } catch (e) {
      DebugLogger.log(
        '[Settings] Secure identity load failed | $e',
        type: 'ERROR',
      );
      if (legacyPrivkey.isNotEmpty) {
        // Migration failed before we could prove secure storage is safe.
        // Keep the legacy Hive secret readable; do not delete it.
        myPrivkey = legacyPrivkey;
        myMnemonic = legacyMnemonic;
        return;
      }
      // No legacy secret exists. A read failure must not be treated as
      // "signed out", otherwise create/import could overwrite an unreadable
      // existing secret.
      myPrivkey = '';
      myMnemonic = '';
      identitySecretsUnavailable = true;
    }
  }

  Future<void> _removeLegacyIdentitySecrets(
    Box settingsBox, {
    bool compact = false,
  }) async {
    final hadLegacy = settingsBox.containsKey('my_privkey') ||
        settingsBox.containsKey('my_mnemonic');
    if (!hadLegacy) return;
    await settingsBox.delete('my_privkey');
    await settingsBox.delete('my_mnemonic');
    if (compact) {
      try {
        await settingsBox.compact();
      } catch (e) {
        DebugLogger.log(
          '[Settings] Settings compaction failed after secret migration | $e',
          type: 'ERROR',
        );
      }
    }
  }

  void _ensureIdentitySecretsAvailable() {
    if (!identitySecretsUnavailable) return;
    throw StateError(
      'Identity secrets are unavailable. Restart the app before creating or restoring an account.',
    );
  }

  Future<void> _restoreIdentitySecrets(
    String? previousPrivkey,
    String? previousMnemonic,
  ) async {
    if (previousPrivkey == null || previousMnemonic == null) return;
    try {
      await _identitySecretStore.write(
        privkey: previousPrivkey,
        mnemonic: previousMnemonic,
      );
    } catch (e) {
      DebugLogger.log(
        '[Settings] Identity secret rollback failed | $e',
        type: 'ERROR',
      );
    }
  }

  Future<void> clearIdentitySecrets() async {
    Object? failure;
    try {
      await _identitySecretStore.clear();
      final remainingPrivkey = await _identitySecretStore.readPrivkey();
      final remainingMnemonic = await _identitySecretStore.readMnemonic();
      if ((remainingPrivkey != null && remainingPrivkey.isNotEmpty) ||
          (remainingMnemonic != null && remainingMnemonic.isNotEmpty)) {
        throw StateError('secure identity secrets still present after clear');
      }
    } catch (e) {
      failure ??= e;
      DebugLogger.log(
        '[Settings] Clear identity secrets failed | $e',
        type: 'ERROR',
      );
    }
    try {
      if (Hive.isBoxOpen('settings')) {
        await _removeLegacyIdentitySecrets(Hive.box('settings'), compact: true);
      }
    } catch (e) {
      failure ??= e;
      DebugLogger.log(
        '[Settings] Clear legacy identity secrets failed | $e',
        type: 'ERROR',
      );
    }
    if (failure != null) {
      throw StateError('identity secrets could not be fully cleared');
    }
  }

  @visibleForTesting
  Future<void> clearIdentitySecretsForTest() async {
    await clearIdentitySecrets();
  }

  static Future<void> _cleanupPlaceholderGlobalIds() async {
    final settingsBox = Hive.box('settings');
    const migrationKey = 'contact_global_id_placeholder_cleanup';
    if (settingsBox.get(migrationKey, defaultValue: false) == true) return;

    try {
      final contactsBox = Hive.box<Contact>('contacts');
      var cleaned = 0;
      for (final key in contactsBox.keys.toList()) {
        final contact = contactsBox.get(key.toString());
        if (contact == null) continue;
        if (contact.globalId != null &&
            Contact.isPlaceholderName(contact.globalId!, contact.pubkey)) {
          contact.globalId = null;
          await contactsBox.put(key, contact);
          cleaned++;
        }
      }
      await settingsBox.put(migrationKey, true);
      if (cleaned > 0) {
        DebugLogger.log(
          '[Settings] Placeholder global ID cleanup done ($cleaned contacts)',
          type: 'SETUP',
        );
      }
    } catch (e) {
      DebugLogger.log('[Settings] Placeholder global ID cleanup failed | $e', type: 'ERROR');
    }
  }

  /// Clears the cached identity from the local contact row for [pubkey].
  ///
  /// Called when a global ID is released locally on disconnect, and from the
  /// kind-0 receiver when a peer's newest profile is bare (no name, no
  /// nip05). [includeGlobalId] is false for the latter: a bare kind-0 is not
  /// proof that the directory released the handle, so the receiver confirms
  /// it with the directory before clearing anything.
  static Future<void> clearContactIdentity(
    String pubkey, {
    bool includeGlobalId = true,
  }) async {
    if (pubkey.isEmpty) return;
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final contact = contactsBox.get(pubkey);
      if (contact == null) return;

      var changed = false;
      if (includeGlobalId && contact.globalId != null) {
        contact.globalId = null;
        changed = true;
      }
      if (!contact.isSaved && contact.name.isNotEmpty) {
        contact.name = '';
        changed = true;
      }
      if (changed) {
        await contactsBox.put(pubkey, contact);
        await ShortcutHelper.pushConversationShortcut(
          id: pubkey,
          name: contact.displayName,
          avatarBytes: null,
        );
      }
    } catch (_) {}
  }

  /// Default display name for a pubkey (fallback when no username is set)
  static String formatDisplayName(String pubkey) {
    if (pubkey.isEmpty) return "User";

    try {
      String npub = KeyUtils.toNpub(pubkey);

      if (npub.length > 16) {
        String prefix = npub.substring(0, 8);
        String suffix = npub.substring(npub.length - 8);
        return "$prefix...$suffix";
      }

      return npub;
    } catch (e) {
      return pubkey.length > 16 ? "${pubkey.substring(0, 8)}...${pubkey.substring(pubkey.length - 8)}" : pubkey;
    }
  }
}

/// The three possible answers from the Chatme directory.
///
/// Keeping "not registered" and "request failed" apart matters: a temporary
/// network error must never erase a valid `name@chatme` handle.
enum DirectoryLookupStatus { found, notFound, failed }

class DirectoryIdentityLookup {
  final DirectoryLookupStatus status;
  final String? name;

  const DirectoryIdentityLookup._(this.status, this.name);

  const DirectoryIdentityLookup.found(String name)
      : this._(DirectoryLookupStatus.found, name);

  const DirectoryIdentityLookup.notFound()
      : this._(DirectoryLookupStatus.notFound, null);

  const DirectoryIdentityLookup.failed()
      : this._(DirectoryLookupStatus.failed, null);

  bool get isFound => status == DirectoryLookupStatus.found;

  /// True when the directory actually answered, whether or not it found a
  /// row. False means the lookup failed and should be retried later.
  bool get isDefinitive => status != DirectoryLookupStatus.failed;
}