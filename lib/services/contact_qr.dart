// contact_qr.dart

import '../core/utils/key_utils.dart';

final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// What the QR code of a profile holds: a nostr: uri with an nprofile.
/// Two relays at most, because every extra relay makes the code denser.
String contactQrPayload(String pubkey, {List<String> relays = const []}) {
  return 'nostr:${KeyUtils.toNprofile(pubkey, relays: relays.take(2).toList())}';
}

/// The public key (hex, lower case) inside scanned text, or null when the text
/// is not a public key. Secret keys are refused on purpose.
String? contactFromScan(String raw) {
  final text = raw.trim();
  final lower = text.toLowerCase();
  final bare = lower.startsWith('nostr:') ? lower.substring(6).trim() : lower;
  if (bare.startsWith('nsec')) return null;

  final hex = KeyUtils.normalizeToHex(text);
  if (!_hex64.hasMatch(hex)) return null;
  return hex.toLowerCase();
}
