// ../core/utils/key_utils.dart

import 'package:bech32/bech32.dart';
import 'package:hex/hex.dart';

class NostrProfilePointer {
  final String pubkey;
  final List<String> relays;

  const NostrProfilePointer(this.pubkey, this.relays);
}

class KeyUtils {
  static const int _maxBech32Length = 5000;

  static String _stripNostrPrefix(String input) {
    final trimmed = input.trim();
    if (trimmed.toLowerCase().startsWith('nostr:')) {
      return trimmed.substring(6).trim();
    }
    return trimmed;
  }

  // pubkey hex + relay hints → nprofile
  static String toNprofile(String hexPubkey, {List<String> relays = const []}) {
    try {
      final pubkeyBytes = HEX.decode(hexPubkey);
      if (pubkeyBytes.length != 32) return hexPubkey;

      final tlv = <int>[0, 32, ...pubkeyBytes];
      for (final relay in relays) {
        final relayBytes = relay.codeUnits;
        if (relayBytes.isEmpty || relayBytes.length > 255) continue;
        tlv
          ..add(1)
          ..add(relayBytes.length)
          ..addAll(relayBytes);
      }

      final data = _convertBits(tlv, 8, 5, true);
      return bech32.encode(Bech32('nprofile', data), _maxBech32Length);
    } catch (e) {
      return hexPubkey;
    }
  }

  // nprofile → pubkey hex and relay hints
  static NostrProfilePointer? decodeNprofile(String input) {
    try {
      final text = _stripNostrPrefix(input).toLowerCase();
      if (text.isEmpty || text.length > _maxBech32Length) return null;

      final decoded = bech32.decode(text, text.length);
      if (decoded.hrp != 'nprofile') return null;

      final bytes = _convertBits(decoded.data, 5, 8, false);
      String? pubkey;
      final relays = <String>[];

      var i = 0;
      while (i < bytes.length) {
        if (i + 2 > bytes.length) return null;
        final type = bytes[i];
        final length = bytes[i + 1];
        final end = i + 2 + length;
        if (end > bytes.length) return null;
        final value = bytes.sublist(i + 2, end);

        if (type == 0 && pubkey == null) {
          if (length != 32) return null;
          pubkey = HEX.encode(value);
        } else if (type == 1) {
          final relay = String.fromCharCodes(value);
          if (relay.startsWith('wss://') || relay.startsWith('ws://')) relays.add(relay);
        }
        i = end;
      }

      if (pubkey == null) return null;
      return NostrProfilePointer(pubkey, relays);
    } catch (e) {
      return null;
    }
  }

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
    final trimmed = _stripNostrPrefix(input);
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('npub')) return fromNpub(lower);
    if (lower.startsWith('nprofile')) return decodeNprofile(lower)?.pubkey ?? trimmed;
    if (lower.startsWith('nsec')) return fromNsec(lower);
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

  // Format display name (npub shortened or fallback)
  static String formatDisplayName(String pubkey) {
    if (pubkey.isEmpty) return "";

    try {
      String npub = toNpub(pubkey);

      if (npub.length > 16) {
        String prefix = npub.substring(0, 8);
        String suffix = npub.substring(npub.length - 8);
        return "$prefix...$suffix";
      }

      return npub;
    } catch (e) {
      return pubkey.length > 8 ? pubkey.substring(0, 8) : pubkey;
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