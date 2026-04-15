// nip44.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'ecdh_engine.dart';

/// NIP-44 v2 — Versioned, Padded, and Authenticated Encryption for Nostr.
///
/// This implementation conforms to the NIP-44 specification using:
/// - ECDH (secp256k1) for shared secret derivation
/// - HKDF-SHA256 for conversation key and per-message key derivation
/// - ChaCha20 for symmetric encryption
/// - HMAC-SHA256 for message authentication (encrypt-then-MAC)
/// - Padded plaintext to reduce message length metadata leakage
///
/// Output format: Base64( version(1) || nonce(32) || ciphertext(n) || mac(32) )
class Nip44 {
  /// Protocol version byte — always 0x02 for NIP-44 v2.
  static const int _version = 2;

  /// Minimum allowed plaintext length after unpadding.
  static const int _minPlaintextSize = 1;

  /// Maximum allowed plaintext length (64 KB).
  static const int _maxPlaintextSize = 65535;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] from [myPriv] to [peerPub] using NIP-44 v2.
  ///
  /// [plaintext]  : The original UTF-8 message to encrypt.
  /// [myPriv]     : Sender's private key as a 64-character lowercase hex string.
  /// [peerPub]    : Recipient's public key as a 64-character hex string (x-only)
  ///                or 66-character compressed form.
  ///
  /// Returns a Base64-encoded payload suitable for use as a Nostr event content.
  /// Throws [Exception] if any cryptographic step fails.
  static Future<String> encrypt(
      String plaintext,
      String myPriv,
      String peerPub,
      ) async {
    try {
      if (plaintext.isEmpty) throw Exception('Plaintext must not be empty');
      if (plaintext.length > _maxPlaintextSize) {
        throw Exception(
          'Plaintext exceeds maximum allowed size of $_maxPlaintextSize bytes',
        );
      }

      // 1. Derive the shared conversation key from the ECDH shared secret.
      final conversationKey = _deriveConversationKey(myPriv, peerPub);

      // 2. Generate a cryptographically secure 32-byte random nonce.
      final nonce = _generateNonce();

      // 3. Derive per-message keys (ChaCha20 key + HMAC key + ChaCha20 nonce).
      final messageKeys = _deriveMessageKeys(conversationKey, nonce);

      // 4. Pad the plaintext to obscure its true length.
      final padded = _pad(utf8.encode(plaintext));

      // 5. Encrypt padded plaintext with ChaCha20 (counter starts at 0).
      final ciphertext = await _chacha20Encrypt(
        messageKeys.encKey,
        messageKeys.chachaNonce,
        padded,
      );

      // 6. Compute HMAC-SHA256 over (nonce || ciphertext) for authentication.
      final mac = _computeHmac(
        messageKeys.hmacKey,
        nonce,
        Uint8List.fromList(ciphertext),
      );

      // 7. Assemble the final payload: version || nonce || ciphertext || mac
      final payload = Uint8List(1 + 32 + ciphertext.length + 32);
      payload[0] = _version;
      payload.setRange(1, 33, nonce);
      payload.setRange(33, 33 + ciphertext.length, ciphertext);
      payload.setRange(33 + ciphertext.length, payload.length, mac);

      return base64.encode(payload);
    } catch (e) {
      throw Exception('NIP-44 encryption failed: $e');
    }
  }

  /// Decrypts a NIP-44 v2 [payload] addressed to [myPriv] from [peerPub].
  ///
  /// [payload]  : Base64-encoded string produced by [encrypt].
  /// [myPriv]   : Recipient's private key as a 64-character hex string.
  /// [peerPub]  : Sender's public key as a 64-character hex string.
  ///
  /// Returns the original UTF-8 plaintext.
  /// Throws [Exception] if the payload is malformed, the version is unsupported,
  /// or MAC verification fails.
  static Future<String> decrypt(
      String payload,
      String myPriv,
      String peerPub,
      ) async {
    try {
      if (payload.isEmpty) throw Exception('Payload must not be empty');

      // 1. Decode from Base64 and validate minimum length.
      //    Minimum: 1 (version) + 32 (nonce) + 32 (mac) + padded min = 99 bytes
      final bytes = base64.decode(payload);
      if (bytes.length < 99) {
        throw Exception('Payload is too short to be a valid NIP-44 v2 message');
      }

      // 2. Validate protocol version byte.
      final version = bytes[0];
      if (version != _version) {
        throw Exception(
          'Unsupported NIP-44 version: $version (expected $_version)',
        );
      }

      // 3. Extract components from the payload.
      final nonce = bytes.sublist(1, 33);
      final mac = bytes.sublist(bytes.length - 32);
      final ciphertext = bytes.sublist(33, bytes.length - 32);

      // 4. Re-derive the same conversation key from ECDH.
      final conversationKey = _deriveConversationKey(myPriv, peerPub);

      // 5. Re-derive the same per-message keys using the embedded nonce.
      final messageKeys = _deriveMessageKeys(
        conversationKey,
        Uint8List.fromList(nonce),
      );

      // 6. Verify the MAC before attempting decryption (authenticate-then-decrypt).
      final expectedMac = _computeHmac(
        messageKeys.hmacKey,
        Uint8List.fromList(nonce),
        Uint8List.fromList(ciphertext),
      );

      if (!_constantTimeEqual(mac, expectedMac)) {
        throw Exception(
          'MAC verification failed — payload may be corrupted or tampered',
        );
      }

      // 7. Decrypt the ciphertext with ChaCha20.
      final padded = await _chacha20Decrypt(
        messageKeys.encKey,
        messageKeys.chachaNonce,
        Uint8List.fromList(ciphertext),
      );

      // 8. Remove padding and decode the original UTF-8 plaintext.
      return utf8.decode(_unpad(Uint8List.fromList(padded)));
    } catch (e) {
      throw Exception('NIP-44 decryption failed: $e');
    }
  }

  /// Returns [true] if [payload] is a structurally valid NIP-44 v2 Base64 string.
  ///
  /// This performs a lightweight structural check only — it does not verify
  /// the MAC or attempt decryption.
  static bool isValidPayload(String payload) {
    try {
      final bytes = base64.decode(payload);
      return bytes.length >= 99 && bytes[0] == _version;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Key Derivation
  // ---------------------------------------------------------------------------

  /// Derives the NIP-44 conversation key from an ECDH shared secret.
  ///
  /// Per the specification: HKDF-SHA256 extract with salt = "nip44-v2"
  /// and IKM = raw 32-byte ECDH x-coordinate.
  static Uint8List _deriveConversationKey(String myPriv, String peerPub) {
    // Obtain the raw 32-byte x-coordinate of the ECDH shared point.
    final sharedX = ECDH.computeSharedSecretRaw(myPriv, peerPub);

    // HKDF-Extract: PRK = HMAC-SHA256(salt, IKM)
    // salt = UTF-8 bytes of "nip44-v2"
    final salt = utf8.encode('nip44-v2');
    final hmac = crypto.Hmac(crypto.sha256, salt);
    final prk = hmac.convert(sharedX).bytes;

    return Uint8List.fromList(prk);
  }

  /// Derives the three per-message keys from [conversationKey] and [nonce].
  ///
  /// Uses HKDF-SHA256 expand with info = "nip44-v2" to produce 76 bytes:
  /// - Bytes  0–31 : ChaCha20 encryption key (32 bytes)
  /// - Bytes 32–43 : ChaCha20 nonce (12 bytes)
  /// - Bytes 44–75 : HMAC-SHA256 authentication key (32 bytes)
  static _MessageKeys _deriveMessageKeys(
      Uint8List conversationKey,
      Uint8List nonce,
      ) {
    // HKDF-Expand with info = nonce, length = 76 bytes.
    final info = nonce;
    final expanded = _hkdfExpand(conversationKey, info, 76);

    return _MessageKeys(
      encKey: expanded.sublist(0, 32),
      chachaNonce: expanded.sublist(32, 44),
      hmacKey: expanded.sublist(44, 76),
    );
  }

  /// HKDF-Expand (RFC 5869 Section 2.3) using HMAC-SHA256.
  ///
  /// Produces [length] bytes of keying material from [prk] and [info].
  static Uint8List _hkdfExpand(Uint8List prk, Uint8List info, int length) {
    final result = <int>[];
    var t = <int>[];
    var counter = 1;

    while (result.length < length) {
      final hmac = crypto.Hmac(crypto.sha256, prk);
      t = hmac.convert([...t, ...info, counter]).bytes;
      result.addAll(t);
      counter++;
    }

    return Uint8List.fromList(result.sublist(0, length));
  }

  // ---------------------------------------------------------------------------
  // Padding
  // ---------------------------------------------------------------------------

  /// Pads [plaintext] bytes to the next power-of-two bucket size.
  ///
  /// The first two bytes of the output encode the original length as a
  /// big-endian unsigned 16-bit integer, followed by the plaintext, then
  /// zero-bytes up to the bucket boundary.
  ///
  /// This reduces metadata leakage by ensuring messages of similar lengths
  /// produce ciphertexts of identical size.
  static Uint8List _pad(List<int> plaintext) {
    final length = plaintext.length;
    if (length < _minPlaintextSize || length > _maxPlaintextSize) {
      throw Exception('Plaintext length $length is outside the valid range');
    }

    // Determine the smallest power-of-two chunk size >= (length + 2).
    final targetSize = _calcPaddedLength(length);

    final padded = Uint8List(targetSize);
    // Write original length as big-endian uint16.
    padded[0] = (length >> 8) & 0xFF;
    padded[1] = length & 0xFF;
    padded.setRange(2, 2 + length, plaintext);
    // Remaining bytes default to 0x00 (zero-padding).

    return padded;
  }

  /// Removes padding from [padded] bytes and returns the original plaintext.
  ///
  /// Reads the original length from the first two bytes and validates it
  /// against the padded buffer size.
  static Uint8List _unpad(Uint8List padded) {
    if (padded.length < 2) {
      throw Exception('Padded buffer is too short to contain a length prefix');
    }

    // Read the original length from the big-endian uint16 prefix.
    final originalLength = (padded[0] << 8) | padded[1];

    if (originalLength < _minPlaintextSize ||
        originalLength > _maxPlaintextSize) {
      throw Exception(
        'Decoded plaintext length $originalLength is outside the valid range',
      );
    }

    if (2 + originalLength > padded.length) {
      throw Exception(
        'Declared plaintext length $originalLength exceeds available buffer',
      );
    }

    return padded.sublist(2, 2 + originalLength);
  }

  /// Calculates the padded output length for a plaintext of [plaintextLength].
  ///
  /// Returns the smallest value in {32, 64, 96, 128, 192, 256, 384, 512, ...}
  /// that is >= (plaintextLength + 2), following the NIP-44 chunk table.
  static int _calcPaddedLength(int plaintextLength) {
    // The +2 accounts for the 16-bit length prefix.
    final required = plaintextLength + 2;

    // Chunk boundaries per the NIP-44 specification.
    const chunks = [
      32, 64, 96, 128, 192, 256, 384, 512, 768, 1024,
      1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384,
      24576, 32768, 49152, 65535,
    ];

    for (final chunk in chunks) {
      if (required <= chunk) return chunk;
    }

    // Fallback — should never be reached given _maxPlaintextSize enforcement.
    return 65535;
  }

  // ---------------------------------------------------------------------------
  // Symmetric Cipher
  // ---------------------------------------------------------------------------

  /// Encrypts [plaintext] bytes using ChaCha20 with the given [key] and [nonce].
  ///
  /// Uses the `cryptography` package's ChaCha20 implementation.
  /// Counter starts at 0 per the NIP-44 specification.
  static Future<List<int>> _chacha20Encrypt(
      Uint8List key,
      Uint8List nonce,
      Uint8List plaintext,
      ) async {
    final algorithm = Chacha20(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(key);
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
    );
    return secretBox.cipherText;
  }

  /// Decrypts [ciphertext] bytes using ChaCha20 with the given [key] and [nonce].
  static Future<List<int>> _chacha20Decrypt(
      Uint8List key,
      Uint8List nonce,
      Uint8List ciphertext,
      ) async {
    final algorithm = Chacha20(macAlgorithm: MacAlgorithm.empty);
    final secretKey = SecretKey(key);
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac.empty,
    );
    return algorithm.decrypt(secretBox, secretKey: secretKey);
  }

  // ---------------------------------------------------------------------------
  // Message Authentication
  // ---------------------------------------------------------------------------

  /// Computes HMAC-SHA256 over the concatenation of [nonce] and [ciphertext].
  ///
  /// The MAC is computed as: HMAC-SHA256(hmacKey, nonce || ciphertext)
  static Uint8List _computeHmac(
      Uint8List hmacKey,
      Uint8List nonce,
      Uint8List ciphertext,
      ) {
    final hmac = crypto.Hmac(crypto.sha256, hmacKey);
    final input = Uint8List(nonce.length + ciphertext.length);
    input.setRange(0, nonce.length, nonce);
    input.setRange(nonce.length, input.length, ciphertext);
    return Uint8List.fromList(hmac.convert(input).bytes);
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Generates a cryptographically secure 32-byte random nonce.
  static Uint8List _generateNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
  }

  /// Performs a constant-time equality check on two byte arrays.
  ///
  /// Prevents timing-based side-channel attacks during MAC verification.
  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

// ---------------------------------------------------------------------------
// Internal Data Classes
// ---------------------------------------------------------------------------

/// Holds the three per-message keys derived by [Nip44._deriveMessageKeys].
class _MessageKeys {
  /// ChaCha20 symmetric encryption key (32 bytes).
  final Uint8List encKey;

  /// ChaCha20 nonce / IV (12 bytes).
  final Uint8List chachaNonce;

  /// HMAC-SHA256 authentication key (32 bytes).
  final Uint8List hmacKey;

  const _MessageKeys({
    required this.encKey,
    required this.chachaNonce,
    required this.hmacKey,
  });
}