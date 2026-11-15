// nip17_file.dart

/// The file related tags of a NIP-17 kind 15 message. The receiver `p` and
/// reply `e` tags are added by the sender code, as for any other rumor.
class FileMessage {
  static const int kind = 15;

  /// The whole file sealed in one AES-GCM block. Used for pictures and voice
  /// notes, which are small enough to keep in memory.
  static const String plainAlgorithm = 'aes-gcm';

  /// The file sealed in chunks while it streams, for videos. See
  /// `stream_crypto.dart` for the layout.
  static const String chunkedAlgorithm = 'aes-gcm-chunked';

  /// The algorithms this client can open.
  static const List<String> supportedAlgorithms = [plainAlgorithm, chunkedAlgorithm];

  final String algorithm;

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

  /// psize: bytes of the file before it was encrypted. For a streamed file
  /// this is the size the receiver will write to disk.
  final int? plainSize;

  /// duration: seconds, a Chatme extra tag for voice notes.
  final int? durationSeconds;

  /// dim: pixel size of a picture, written as widthxheight.
  final int? width;
  final int? height;

  const FileMessage({
    required this.url,
    required this.mimeType,
    required this.key,
    required this.nonce,
    required this.hash,
    this.algorithm = plainAlgorithm,
    this.originalHash,
    this.size,
    this.plainSize,
    this.durationSeconds,
    this.width,
    this.height,
  });

  bool get isAudio => mimeType.startsWith('audio/');

  bool get isImage => mimeType.startsWith('image/');

  bool get isVideo => mimeType.startsWith('video/');

  /// True when the file must be opened with the chunked reader.
  bool get isStreamed => algorithm == chunkedAlgorithm;

  /// What the chat list and notifications show for this file.
  String get previewLabel {
    if (isAudio) return 'Voice message';
    if (isImage) return 'Photo';
    if (isVideo) return 'Video';
    return 'File';
  }

  static final RegExp _dim = RegExp(r'^(\d{1,5})x(\d{1,5})$');

  /// Reads a `dim` value. Returns null for anything that is not a sane size.
  static ({int width, int height})? parseDim(String? value) {
    if (value == null) return null;
    final match = _dim.firstMatch(value);
    if (match == null) return null;
    final width = int.parse(match.group(1)!);
    final height = int.parse(match.group(2)!);
    if (width < 1 || height < 1) return null;
    return (width: width, height: height);
  }

  /// The tags of the whole rumor: who it is for, what it replies to, and the file.
  List<List<String>> rumorTags({required String receiver, String? replyToId}) => [
        ['p', receiver],
        if (replyToId != null && replyToId.isNotEmpty) ['e', replyToId],
        ...toTags(),
      ];

  Map<String, String> toMap() => {
        'url': url,
        'type': mimeType,
        'key': key,
        'nonce': nonce,
        'x': hash,
        if (algorithm != plainAlgorithm) 'alg': algorithm,
        if (originalHash != null) 'ox': originalHash!,
        if (size != null) 'size': '$size',
        if (plainSize != null) 'psize': '$plainSize',
        if (durationSeconds != null) 'duration': '$durationSeconds',
        if (width != null && height != null) 'dim': '${width}x$height',
      };

  /// Reads what [toMap] wrote. Returns null when a required value is missing.
  static FileMessage? fromMap(Map<String, String> map) {
    final url = map['url'];
    final type = map['type'];
    final key = map['key'];
    final nonce = map['nonce'];
    final hash = map['x'];
    if (url == null || type == null || key == null || nonce == null || hash == null) {
      return null;
    }
    return FileMessage(
      url: url,
      mimeType: type,
      key: key,
      nonce: nonce,
      hash: hash,
      algorithm: map['alg'] ?? plainAlgorithm,
      originalHash: map['ox'],
      size: int.tryParse(map['size'] ?? ''),
      plainSize: int.tryParse(map['psize'] ?? ''),
      durationSeconds: int.tryParse(map['duration'] ?? ''),
      width: parseDim(map['dim'])?.width,
      height: parseDim(map['dim'])?.height,
    );
  }

  List<List<String>> toTags() => [
        ['file-type', mimeType],
        ['encryption-algorithm', algorithm],
        ['decryption-key', key],
        ['decryption-nonce', nonce],
        ['x', hash],
        if (originalHash != null) ['ox', originalHash!],
        if (size != null) ['size', '$size'],
        if (plainSize != null) ['psize', '$plainSize'],
        if (durationSeconds != null) ['duration', '$durationSeconds'],
        if (width != null && height != null) ['dim', '${width}x$height'],
      ];

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]+$');

  static bool _isHex(String? value, List<int> lengths) {
    return value != null && lengths.contains(value.length) && _hex.hasMatch(value);
  }

  /// Reads a kind 15 rumor. Returns null when it is not a file we can use:
  /// a missing or wrong tag, an algorithm this client cannot open, or an
  /// address that is not https.
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
    final algorithm = values['encryption-algorithm'];
    if (algorithm == null || !supportedAlgorithms.contains(algorithm)) return null;

    final key = values['decryption-key'];
    final nonce = values['decryption-nonce'];
    final hash = values['x'];
    final originalHash = values['ox'];
    if (!_isHex(key, [64])) return null;
    if (!_isHex(nonce, [24, 32])) return null;
    if (!_isHex(hash, [64])) return null;
    if (originalHash != null && !_isHex(originalHash, [64])) return null;

    final size = int.tryParse(values['size'] ?? '');
    final plainSize = int.tryParse(values['psize'] ?? '');
    final duration = int.tryParse(values['duration'] ?? '');
    final dim = parseDim(values['dim']);

    return FileMessage(
      url: url,
      mimeType: mimeType,
      key: key!.toLowerCase(),
      nonce: nonce!.toLowerCase(),
      hash: hash!.toLowerCase(),
      algorithm: algorithm,
      originalHash: originalHash?.toLowerCase(),
      size: size != null && size >= 0 ? size : null,
      plainSize: plainSize != null && plainSize >= 0 ? plainSize : null,
      durationSeconds: duration != null && duration >= 0 ? duration : null,
      width: dim?.width,
      height: dim?.height,
    );
  }
}
