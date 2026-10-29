// nip17_file.dart

/// The file related tags of a NIP-17 kind 15 message. The receiver `p` and
/// reply `e` tags are added by the sender code, as for any other rumor.
class FileMessage {
  static const int kind = 15;
  static const String algorithm = 'aes-gcm';

  final String url;
  final String mimeType;
  final String key;
  final String nonce;

  /// x: sha256 of the encrypted file.
  final String hash;

  /// ox: sha256 of the original file.
  final String? originalHash;

  /// size: bytes of the encrypted file.
  final int? size;

  /// duration: seconds, a Chatme extra tag for voice notes.
  final int? durationSeconds;

  const FileMessage({
    required this.url,
    required this.mimeType,
    required this.key,
    required this.nonce,
    required this.hash,
    this.originalHash,
    this.size,
    this.durationSeconds,
  });

  bool get isAudio => mimeType.startsWith('audio/');

  List<List<String>> toTags() => [
        ['file-type', mimeType],
        ['encryption-algorithm', algorithm],
        ['decryption-key', key],
        ['decryption-nonce', nonce],
        ['x', hash],
        if (originalHash != null) ['ox', originalHash!],
        if (size != null) ['size', '$size'],
        if (durationSeconds != null) ['duration', '$durationSeconds'],
      ];

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  static bool _isHex(String? value, List<int> lengths) {
    return value != null && lengths.contains(value.length) && _hex.hasMatch(value);
  }

  /// Reads a kind 15 rumor. Returns null when it is not a file we can use:
  /// a missing or wrong tag, another algorithm, or an address that is not https.
  static FileMessage? parse({required String content, required List tags}) {
    final values = <String, String>{};
    for (final tag in tags) {
      if (tag is List && tag.length >= 2 && tag[0] is String && tag[1] is String) {
        values.putIfAbsent(tag[0] as String, () => tag[1] as String);
      }
    }

    final url = content.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;

    final mimeType = values['file-type'];
    if (mimeType == null || mimeType.isEmpty) return null;
    if (values['encryption-algorithm'] != algorithm) return null;

    final key = values['decryption-key'];
    final nonce = values['decryption-nonce'];
    final hash = values['x'];
    final originalHash = values['ox'];
    if (!_isHex(key, [64])) return null;
    if (!_isHex(nonce, [24, 32])) return null;
    if (!_isHex(hash, [64])) return null;
    if (originalHash != null && !_isHex(originalHash, [64])) return null;

    final size = int.tryParse(values['size'] ?? '');
    final duration = int.tryParse(values['duration'] ?? '');

    return FileMessage(
      url: url,
      mimeType: mimeType,
      key: key!.toLowerCase(),
      nonce: nonce!.toLowerCase(),
      hash: hash!.toLowerCase(),
      originalHash: originalHash?.toLowerCase(),
      size: size != null && size >= 0 ? size : null,
      durationSeconds: duration != null && duration >= 0 ? duration : null,
    );
  }
}
