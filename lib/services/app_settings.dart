// app_settings.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:crypto/crypto.dart';
import 'package:bip340/bip340.dart' as bip340;
import '../core/crypto/key_generator.dart';
import '../core/utils/debug_logger.dart';
import '../core/utils/key_utils.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class AppSettings {
  static final AppSettings _instance = AppSettings._internal();
  factory AppSettings() => _instance;
  AppSettings._internal();

  static AppSettings get instance => _instance;

  bool isNip05Verified = false;
  String myPubkey = '';
  String myPrivkey = '';
  String myName = '';
  String myMnemonic = '';
  String myNip05 = '';
  String myPhotoPath = '';
  String myPhotoUrl = '';
  ThemeMode themeMode = ThemeMode.dark;

  Future<void> load() async {
    try {
      final settingsBox = Hive.box('settings');

      // Load persisted values
      myPubkey = settingsBox.get('my_pubkey', defaultValue: '');
      myPrivkey = settingsBox.get('my_privkey', defaultValue: '');
      myMnemonic = settingsBox.get('my_mnemonic', defaultValue: '');
      myNip05 = settingsBox.get('my_nip05', defaultValue: '');
      myPhotoPath = settingsBox.get('my_photo_path', defaultValue: '');
      myPhotoUrl = settingsBox.get('my_photo_url', defaultValue: '');
      isNip05Verified = settingsBox.get('is_nip05_verified', defaultValue: false);
      myName = settingsBox.get('my_name', defaultValue: '');

      // Generate new identity if first launch
      if (myPubkey.isEmpty) {
        final keypair = _generateNostrKeypair();
        myPubkey = keypair['public']!;
        myPrivkey = keypair['private']!;
        myName = formatDisplayName(myPubkey);

        await settingsBox.put('my_pubkey', myPubkey);
        await settingsBox.put('my_privkey', myPrivkey);
        await settingsBox.put('my_name', myName);

        DebugLogger.log('[Settings] Generated new Nostr identity: ${myPubkey.substring(0, 16)}...', type: 'SETUP');
      }

      // Load theme
      final savedTheme = settingsBox.get('theme_mode', defaultValue: 'system');
      themeMode = savedTheme == 'dark' ? ThemeMode.dark : (savedTheme == 'light' ? ThemeMode.light : ThemeMode.system);

      DebugLogger.log('[Settings] Loaded. Pubkey: ${myPubkey.substring(0, 16)}...', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('[Settings] Load failed | $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<String?> _fetchNameFromFirebase(String pubkey) async {
    try {
      const String rtdbUrl = "https://chatme-412d1-default-rtdb.asia-southeast1.firebasedatabase.app";
      final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: rtdbUrl);
      final snapshot = await db.ref("users/$pubkey").get().timeout(const Duration(seconds: 10));
      if (snapshot.exists) return snapshot.value as String?;
      return null;
    } catch (e) {
      DebugLogger.log('[Settings] Fetch name from Firebase failed | $e', type: 'ERROR');
      return null;
    }
  }

  Future<void> importAccount(String input) async {
    try {
      final settingsBox = Hive.box('settings');
      final cleaned = input.trim();

      if (cleaned.startsWith('nsec')) {
        myPrivkey = KeyUtils.fromNsec(cleaned);
        myMnemonic = '';
      } else if (cleaned.split(' ').length >= 12) {
        myPrivkey = await ChatMeVault.deriveNostrPrivateKey(cleaned);
        myMnemonic = cleaned;
      } else if (cleaned.length == 64) {
        myPrivkey = cleaned;
        myMnemonic = '';
      } else {
        throw 'Invalid input format. Use nsec, 64-char hex, or 12 words.';
      }

      if (myPrivkey.length != 64) {
        throw 'Invalid private key format.';
      }

      myPubkey = bip340.getPublicKey(myPrivkey);

      // Try to fetch existing display name from Firebase
      final fetchedName = await _fetchNameFromFirebase(myPubkey);
      myName = fetchedName ?? formatDisplayName(myPubkey);

      if (fetchedName != null) {
        myNip05 = '$fetchedName@chatme';
        isNip05Verified = true;
      } else {
        myNip05 = '';
        isNip05Verified = false;
      }

      await settingsBox.putAll({
        'my_pubkey': myPubkey,
        'my_privkey': myPrivkey,
        'my_mnemonic': myMnemonic,
        'my_name': myName,
        'my_nip05': myNip05,
        'is_nip05_verified': isNip05Verified,
      });

      DebugLogger.log('[Settings] Account restored: $myPubkey', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('[Settings] Import account failed | $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> saveTheme(ThemeMode mode) async {
    themeMode = mode;
    String themeString = (mode == ThemeMode.dark) ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system');
    await Hive.box('settings').put('theme_mode', themeString);
  }

  Future<void> savePhotoPath(String path) async {
    myPhotoPath = path;
    await Hive.box('settings').put('my_photo_path', path);
  }

  Future<void> savePhotoUrl(String url) async {
    myPhotoUrl = url;
    await Hive.box('settings').put('my_photo_url', url);
  }

  Future<void> loadPhotoPath() async {
    myPhotoPath = Hive.box('settings').get('my_photo_path', defaultValue: '');
  }

  Future<void> updateNip05(String newNip05, bool verified) async {
    myNip05 = newNip05;
    isNip05Verified = verified;
    await Hive.box('settings').put('my_nip05', newNip05);
    await Hive.box('settings').put('is_nip05_verified', verified);
    DebugLogger.log('[Settings] Identity updated: $newNip05 (verified: $verified)', type: 'SETUP');
  }

  Future<Map<String, dynamic>> backupKeys() async {
    try {
      final backupData = {
        'public_key': myPubkey,
        'private_key': myPrivkey,
        'name': myName,
        'backup_date': DateTime.now().toIso8601String(),
        'app': 'ChatMe',
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

  Map<String, String> _generateNostrKeypair() {
    try {
      final mnemonic = ChatMeVault.generateNewMnemonic();
      myMnemonic = mnemonic;

      final bytes = utf8.encode(mnemonic);
      final privateKey = sha256.convert(bytes).toString();
      final publicKey = bip340.getPublicKey(privateKey);

      final settingsBox = Hive.box('settings');
      settingsBox.put('my_mnemonic', mnemonic);
      settingsBox.put('my_pubkey', publicKey);
      settingsBox.put('my_privkey', privateKey);

      return {'private': privateKey, 'public': publicKey};
    } catch (e) {
      DebugLogger.log('[Settings] Generate keypair failed | $e', type: 'ERROR');
      rethrow;
    }
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
      return "User ${pubkey.substring(0, 8)}";
    }
  }
}