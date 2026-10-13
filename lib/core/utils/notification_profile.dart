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

  static Future<NotificationProfile> resolve(String pubkey) async {
    await _ensureBoxes();
    final name = _resolveName(pubkey);
    final avatar = await _buildAvatar(pubkey, name);
    return NotificationProfile(name, avatar);
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

  static String _resolveName(String pubkey) {
    try {
      final contact = Hive.box<Contact>('contacts').get(pubkey);
      if (contact != null) return contact.displayName;
    } catch (_) {}
    return KeyUtils.formatDisplayName(pubkey);
  }

  // -------------------------------------------------------------- avatar

  static String? _photoUrl(String pubkey) {
    try {
      final url = Hive.box<String>('profile_pictures').get(pubkey);
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {}
    return null;
  }

  static Future<Uint8List?> _buildAvatar(String pubkey, String name) async {
    try {
      final url = _photoUrl(pubkey);
      if (url != null) {
        final photo = await _circlePhoto(url);
        if (photo != null) return photo;
      }
      return await _initialsAvatar(pubkey, name);
    } catch (_) {
      return null;
    }
  }

  /// Photo from the same cache cached_network_image uses (key = url).
  /// If it is not cached yet, tries to download for at most 3 seconds.
  static Future<Uint8List?> _circlePhoto(String url) async {
    try {
      final file = await DefaultCacheManager()
          .getSingleFile(url)
          .timeout(const Duration(seconds: 3));
      final bytes = await file.readAsBytes();

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