// ../core/utils/key_utils.dart

import 'package:bech32/bech32.dart';
import 'package:hex/hex.dart';

class KeyUtils {

  // hex → npub
  static String toNpub(String hexPubkey) {
    try {
      final decoded = HEX.decode(hexPubkey);
      final converted = _convertBits(decoded, 8, 5, true);
      return bech32.encode(Bech32('npub', converted));
    } catch (e) {
      return hexPubkey;
    }
  }

  // hex → nsec
  static String toNsec(String hexPrivkey) {
    try {
      final decoded = HEX.decode(hexPrivkey);
      final converted = _convertBits(decoded, 8, 5, true);
      return bech32.encode(Bech32('nsec', converted));
    } catch (e) {
      return hexPrivkey;
    }
  }

  // npub → hex
  static String fromNpub(String npub) {
    try {
      final decoded = bech32.decode(npub);
      final converted = _convertBits(decoded.data, 5, 8, false);
      return HEX.encode(converted);
    } catch (e) {
      return npub;
    }
  }

  // nsec → hex
  static String fromNsec(String nsec) {
    try {
      final decoded = bech32.decode(nsec);
      final converted = _convertBits(decoded.data, 5, 8, false);
      return HEX.encode(converted);
    } catch (e) {
      return nsec;
    }
  }

  // Auto detect dan normalize ke hex
  static String normalizeToHex(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('npub')) return fromNpub(trimmed);
    if (trimmed.startsWith('nsec')) return fromNsec(trimmed);
    return trimmed;
  }

  // Cek validitas
  static bool isValidNpub(String input) {
    try {
      final hex = fromNpub(input);
      return hex.length == 64;
    } catch (e) {
      return false;
    }
  }

  static bool isValidNsec(String input) {
    try {
      final hex = fromNsec(input);
      return hex.length == 64;
    } catch (e) {
      return false;
    }
  }

  // Helper convertBits untuk bech32
  static List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    int acc = 0;
    int bits = 0;
    final result = <int>[];
    final maxv = (1 << to) - 1;

    for (final value in data) {
      acc = ((acc << from) | value);
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) result.add((acc << (to - bits)) & maxv);
    } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }

    return result;
  }
}