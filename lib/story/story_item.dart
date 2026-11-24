class StoryItem {
  static const Duration defaultDuration = Duration(hours: 24);

  final String id;
  final String authorPubkey;
  final int createdAt;
  final int expiresAt;
  final String mediaUrl;
  final String mimeType;
  final String encryptionKey;
  final String encryptionNonce;
  final String fileHash;
  final String originalHash;
  final String caption;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final int? size;
  final String localPath;
  final Map<String, int> viewedBy;

  /// One-use Blossom auth key kept only by stories we posted, so the blob can
  /// be deleted at expiry, on logout or when the user deletes the story.
  final String uploadPrivkey;
  final String uploadPubkey;

  const StoryItem({
    required this.id,
    required this.authorPubkey,
    required this.createdAt,
    required this.expiresAt,
    required this.mediaUrl,
    required this.mimeType,
    required this.encryptionKey,
    required this.encryptionNonce,
    required this.fileHash,
    required this.originalHash,
    this.caption = '',
    this.width,
    this.height,
    this.durationSeconds,
    this.size,
    this.localPath = '',
    this.viewedBy = const {},
    this.uploadPrivkey = '',
    this.uploadPubkey = '',
  });

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');

  bool isExpiredAt(int nowMs) => nowMs >= expiresAt;

  StoryItem copyWith({
    String? id,
    String? authorPubkey,
    int? createdAt,
    int? expiresAt,
    String? mediaUrl,
    String? mimeType,
    String? encryptionKey,
    String? encryptionNonce,
    String? fileHash,
    String? originalHash,
    String? caption,
    int? width,
    int? height,
    int? durationSeconds,
    int? size,
    String? localPath,
    Map<String, int>? viewedBy,
    String? uploadPrivkey,
    String? uploadPubkey,
  }) {
    return StoryItem(
      id: id ?? this.id,
      authorPubkey: authorPubkey ?? this.authorPubkey,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mimeType: mimeType ?? this.mimeType,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      encryptionNonce: encryptionNonce ?? this.encryptionNonce,
      fileHash: fileHash ?? this.fileHash,
      originalHash: originalHash ?? this.originalHash,
      caption: caption ?? this.caption,
      width: width ?? this.width,
      height: height ?? this.height,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      size: size ?? this.size,
      localPath: localPath ?? this.localPath,
      viewedBy: viewedBy ?? Map<String, int>.from(this.viewedBy),
      uploadPrivkey: uploadPrivkey ?? this.uploadPrivkey,
      uploadPubkey: uploadPubkey ?? this.uploadPubkey,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'authorPubkey': authorPubkey,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
        'mediaUrl': mediaUrl,
        'mimeType': mimeType,
        'encryptionKey': encryptionKey,
        'encryptionNonce': encryptionNonce,
        'fileHash': fileHash,
        'originalHash': originalHash,
        'caption': caption,
        'width': width,
        'height': height,
        'durationSeconds': durationSeconds,
        'size': size,
        'localPath': localPath,
        'viewedBy': viewedBy,
        'uploadPrivkey': uploadPrivkey,
        'uploadPubkey': uploadPubkey,
      };

  factory StoryItem.fromMap(Map<dynamic, dynamic> map) {
    final rawViewed = map['viewedBy'];
    final viewedBy = <String, int>{};
    if (rawViewed is Map) {
      for (final entry in rawViewed.entries) {
        final key = entry.key?.toString() ?? '';
        final value = entry.value;
        if (key.isEmpty || value is! int) continue;
        viewedBy[key] = value;
      }
    }

    int? parseInt(dynamic value) {
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '');
    }

    return StoryItem(
      id: map['id']?.toString() ?? '',
      authorPubkey: map['authorPubkey']?.toString() ?? '',
      createdAt: parseInt(map['createdAt']) ?? 0,
      expiresAt: parseInt(map['expiresAt']) ?? 0,
      mediaUrl: map['mediaUrl']?.toString() ?? '',
      mimeType: map['mimeType']?.toString() ?? '',
      encryptionKey: map['encryptionKey']?.toString() ?? '',
      encryptionNonce: map['encryptionNonce']?.toString() ?? '',
      fileHash: map['fileHash']?.toString() ?? '',
      originalHash: map['originalHash']?.toString() ?? '',
      caption: map['caption']?.toString() ?? '',
      width: parseInt(map['width']),
      height: parseInt(map['height']),
      durationSeconds: parseInt(map['durationSeconds']),
      size: parseInt(map['size']),
      localPath: map['localPath']?.toString() ?? '',
      viewedBy: viewedBy,
      uploadPrivkey: map['uploadPrivkey']?.toString() ?? '',
      uploadPubkey: map['uploadPubkey']?.toString() ?? '',
    );
  }
}
