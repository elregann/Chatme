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
  ThemeMode themeMode = ThemeMode.dark;

  Future<void> load() async {
    try {
      final settingsBox = Hive.box('settings');

      // 1. Ambil data yang sudah ada
      myPubkey = settingsBox.get('my_pubkey', defaultValue: '');
      myPrivkey = settingsBox.get('my_privkey', defaultValue: '');
      myMnemonic = settingsBox.get('my_mnemonic', defaultValue: '');
      myNip05 = settingsBox.get('my_nip05', defaultValue: '');
      isNip05Verified = settingsBox.get('is_nip05_verified', defaultValue: false);

      // Ambil nama yang sudah tersimpan
      myName = settingsBox.get('my_name', defaultValue: '');

      // 2. Cek kalau User Baru (Pubkey masih kosong)
      if (myPubkey.isEmpty) {
        final keypair = _generateNostrKeypair();
        myPubkey = keypair['public']!;
        myPrivkey = keypair['private']!;

        // BARU DI SINI KITA BUAT NAMANYA pakai Pubkey yang baru jadi
        myName = formatDisplayName(myPubkey);

        await settingsBox.put('my_pubkey', myPubkey);
        await settingsBox.put('my_privkey', myPrivkey);
        await settingsBox.put('my_name', myName);

        DebugLogger.log('Generated new Nostr identity: ${myPubkey.substring(0, 16)}...', type: 'SETUP');
      }

      // 3. Logika Tema (tetap sama)
      final savedTheme = settingsBox.get('theme_mode', defaultValue: 'system');
      themeMode = savedTheme == 'dark' ? ThemeMode.dark : (savedTheme == 'light' ? ThemeMode.light : ThemeMode.system);

      DebugLogger.log('Settings loaded. Pubkey: ${myPubkey.substring(0, 16)}...', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('Error loading settings: $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> importAccount(String input) async {
    try {
      final settingsBox = Hive.box('settings');
      final cleaned = input.trim().replaceAll(RegExp(r'\s+'), ' ');

      if (cleaned.split(' ').length >= 12) {
        myPrivkey = await ChatMeVault.deriveNostrPrivateKey(cleaned);
        myMnemonic = cleaned;
      } else if (cleaned.length == 64) {
        myPrivkey = cleaned;
        myMnemonic = '';
      } else {
        throw 'Invalid input format. Use 64-char hex or 12 words.';
      }

      myPubkey = bip340.getPublicKey(myPrivkey);

      await settingsBox.putAll({
        'my_pubkey': myPubkey,
        'my_privkey': myPrivkey,
        'my_mnemonic': myMnemonic,
      });

      DebugLogger.log('✅ Account restored: $myPubkey', type: 'SETUP');
    } catch (e) {
      DebugLogger.log('❌ Failed to import account: $e', type: 'ERROR');
      rethrow;
    }
  }

  Future<void> saveTheme(ThemeMode mode) async {
    themeMode = mode;
    String themeString = (mode == ThemeMode.dark) ? 'dark' : (mode == ThemeMode.light ? 'light' : 'system');
    await Hive.box('settings').put('theme_mode', themeString);
  }

  Future<void> updateNip05(String newNip05, bool verified) async {
    myNip05 = newNip05;
    isNip05Verified = verified;
    await Hive.box('settings').put('my_nip05', newNip05);
    await Hive.box('settings').put('is_nip05_verified', verified);
    DebugLogger.log('Identity updated: $newNip05 (Verified: $verified)', type: 'SETUP');
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
      DebugLogger.log('Keys backed up to clipboard', type: 'SETUP');
      return backupData;
    } catch (e) {
      DebugLogger.log('Error backing up keys: $e', type: 'ERROR');
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
      DebugLogger.log('Error generating keypair: $e', type: 'ERROR');
      rethrow;
    }
  }

  //Default name for new user
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