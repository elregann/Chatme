// lib/core/utils/notification_profile.dart
//
// Resolves the name + avatar image shown in chat notifications, using the
// SAME rules as the in-app UI (Contact.displayName, profile_pictures cache,
// UserAvatar fallback = colored circle + initial).
//
// Safe to call from both the foreground isolate and the FCM background
// isolate (opens the needed Hive boxes read-only if they are not open yet).

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../../models/contact.dart';
import 'key_utils.dart';
import 'ui_utils.dart';

class NotificationProfile {
  final String name;

  /// Circular PNG avatar (photo, or colored circle with initial).
  /// Null only if drawing failed; callers should then skip the icon.
  final Uint8List? avatarPng;

  const NotificationProfile(this.name, this.avatarPng);

  static const int _size = 192; // px

  /// Small in-memory cache so the notification avatar is not regenerated every
  /// time the foreground-service notification is updated (connecting →
  /// active → reconnecting). Keyed by pubkey + name + photo URL, so a rename
  /// or a new profile picture still refreshes immediately.
  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};
  static const int _cacheLimit = 32;
  static const Duration _avatarTtl = Duration(minutes: 5);
  static const Duration _failedAvatarTtl = Duration(seconds: 30);

  /// [allowDownload] false uses only the already cached photo (never waits on
  /// the network) and falls back to the initials avatar, for callers that must
  /// stay fast, such as launcher shortcuts pushed from the UI.
  ///
  /// [nameHint] is the sender's own name carried by a push. It only replaces
  /// the name of an unsaved contact, see [pickName].
  ///
  /// [avatarHint] is the sender's thumbnail URL carried by a push.
  static Future<NotificationProfile> resolve(
    String pubkey, {
    bool allowDownload = true,
    String? nameHint,
    String? avatarHint,
  }) async {
    await _ensureBoxes();
    final name = _resolveName(pubkey, nameHint);
    final photoUrl = _resolvePhotoUrl(pubkey, avatarHint);
    // Cache separately so a cached-only avatar never hides a later download.
    final cacheKey =
        '$pubkey|$name|${photoUrl ?? ''}${allowDownload ? '' : '|cached'}';

    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.profile;
    }

    final avatar = await _buildAvatar(pubkey, name, photoUrl, allowDownload);
    final profile = NotificationProfile(name, avatar);

    if (_cache.length >= _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    _cache[cacheKey] = _CacheEntry(profile, avatar != null);
    return profile;
  }

  // ---------------------------------------------------------------- boxes

  static Future<void> _ensureBoxes() async {
    try {
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(ContactAdapter());
      }
      // compactionStrategy false: this isolate must never rewrite box files.
      if (!Hive.isBoxOpen('contacts')) {
        await Hive.openBox<Contact>(
          'contacts',
          compactionStrategy: (_, __) => false,
        );
      }
      if (!Hive.isBoxOpen('profile_pictures')) {
        await Hive.openBox<String>(
          'profile_pictures',
          compactionStrategy: (_, __) => false,
        );
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- name

  static String _resolveName(String pubkey, String? nameHint) {
    Contact? contact;
    try {
      contact = Hive.box<Contact>('contacts').get(pubkey);
    } catch (_) {}
    return pickName(pubkey: pubkey, contact: contact, hint: nameHint);
  }

  /// A name the user saved always wins. For an unsaved contact the hint is the
  /// sender's current name, fresher than a profile this device has not fetched
  /// yet. Strangers (no contact row) and unusable hints keep the old rules.
  static String pickName({
    required String pubkey,
    Contact? contact,
    String? hint,
  }) {
    if (contact == null) return KeyUtils.formatDisplayName(pubkey);
    if (!contact.isSaved) {
      final fresh = cleanNameHint(hint, pubkey);
      if (fresh != null) return fresh;
    }
    return contact.displayName;
  }

  static const int _maxHintRunes = 64;

  /// Returns a notification-safe name, or null when the hint is empty or only
  /// a placeholder such as an npub stub.
  static String? cleanNameHint(String? hint, String pubkey) {
    if (hint == null) return null;
    final cleaned = hint
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty || Contact.isPlaceholderName(cleaned, pubkey)) {
      return null;
    }
    final runes = cleaned.runes;
    if (runes.length <= _maxHintRunes) return cleaned;
    return String.fromCharCodes(runes.take(_maxHintRunes)).trim();
  }

  // -------------------------------------------------------------- avatar

  static String? _resolvePhotoUrl(String pubkey, String? avatarHint) {
    final fresh = cleanAvatarHint(avatarHint);
    if (fresh != null) return fresh;
    return _photoUrl(pubkey);
  }

  /// Returns a valid https avatar URL, or null when the hint is absent or malformed.
  static String? cleanAvatarHint(String? hint) {
    if (hint == null) return null;
    final trimmed = hint.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return trimmed;
  }

  static String? _photoUrl(String pubkey) {
    try {
      final url = Hive.box<String>('profile_pictures').get(pubkey);
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {}
    return null;
  }

  static Future<Uint8List?> _buildAvatar(
    String pubkey,
    String name,
    String? photoUrl,
    bool allowDownload,
  ) async {
    try {
      if (photoUrl != null) {
        final photo =
            await _circlePhoto(photoUrl, allowDownload: allowDownload);
        if (photo != null) return photo;
      }
      return await _initialsAvatar(pubkey, name);
    } catch (_) {
      return null;
    }
  }

  /// Photo from network or cache.
  /// Downloads directly via HTTP so it works reliably in both the foreground
  /// and the background FCM isolate without depending on sqflite.
  static Future<Uint8List?> _circlePhoto(
    String url, {
    required bool allowDownload,
  }) async {
    try {
      Uint8List? bytes;
      if (allowDownload) {
        try {
          final res = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 3));
          if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
            bytes = res.bodyBytes;
            // Best effort cache population for in-app widgets
            try {
              DefaultCacheManager().putFile(url, bytes);
            } catch (_) {}
          }
        } catch (_) {}
      }

      if (bytes == null) {
        try {
          final file =
              (await DefaultCacheManager().getFileFromCache(url))?.file;
          bytes = await file?.readAsBytes();
        } catch (_) {}
      }

      if (bytes == null || bytes.isEmpty) return null;

      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 512);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      final s = _size.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.clipPath(ui.Path()..addOval(ui.Rect.fromLTWH(0, 0, s, s)));

      // Center-crop to a square (same look as CircleAvatar backgroundImage).
      final side = image.width < image.height
          ? image.width.toDouble()
          : image.height.toDouble();
      final src = ui.Rect.fromLTWH(
        (image.width - side) / 2,
        (image.height - side) / 2,
        side,
        side,
      );
      canvas.drawImageRect(
        image,
        src,
        ui.Rect.fromLTWH(0, 0, s, s),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );

      return await _toPng(recorder);
    } catch (_) {
      return null; // caller falls back to initials
    }
  }

  /// Same as UserAvatar._buildFallback: colored circle + first letter.
  static Future<Uint8List?> _initialsAvatar(String pubkey, String name) async {
    try {
      final s = _size.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);

      canvas.drawCircle(
        ui.Offset(s / 2, s / 2),
        s / 2,
        ui.Paint()..color = UIUtils.getAvatarColor(pubkey),
      );

      // UserAvatar uses fontSize = radius * 0.7  ->  diameter * 0.35
      final painter = TextPainter(
        text: TextSpan(
          text: UIUtils.getInitials(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: s * 0.35,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      painter.paint(
        canvas,
        ui.Offset((s - painter.width) / 2, (s - painter.height) / 2),
      );

      return await _toPng(recorder);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _toPng(ui.PictureRecorder recorder) async {
    final picture = recorder.endRecording();
    final img = await picture.toImage(_size, _size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

class _CacheEntry {
  final NotificationProfile profile;
  final bool hasAvatar;
  final DateTime createdAt;

  _CacheEntry(this.profile, this.hasAvatar) : createdAt = DateTime.now();

  bool get isExpired {
    final ttl = hasAvatar
        ? NotificationProfile._avatarTtl
        : NotificationProfile._failedAvatarTtl;
    return DateTime.now().difference(createdAt) > ttl;
  }
}
