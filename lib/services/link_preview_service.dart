// link_preview_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../core/utils/link_utils.dart';
import 'app_settings.dart';

class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  const LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  /// Always taken from the link itself, never from what the page claims.
  String get host => Uri.tryParse(url)?.host ?? '';

  bool get isEmpty => title == null && description == null && imageUrl == null;
}

class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  // Only successful previews are kept. A failure is remembered in memory for
  // a short time so a list that rebuilds does not hammer the same dead link.
  final Map<String, LinkPreviewData> _cache = {};
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Future<LinkPreviewData?>> _inFlight = {};

  static const Duration _ttl = Duration(days: 7);
  static const Duration _retryAfter = Duration(seconds: 60);
  Box<String>? _box;

  static bool get _enabled => AppSettings.instance.linkPreviewsEnabled;

  Future<void> init() async {
    _box = await Hive.openBox<String>('link_previews');
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = _box!.keys.where((k) {
      try {
        final m = jsonDecode(_box!.get(k)!) as Map<String, dynamic>;
        return now - (m['t'] as int) > _ttl.inMilliseconds;
      } catch (_) {
        return true;
      }
    }).toList();
    await _box!.deleteAll(expired);
  }

  Future<void> clear() async {
    _cache.clear();
    _failedAt.clear();
    await _box?.clear();
  }

  LinkPreviewData? _readFromDisk(String url) {
    final raw = _box?.get(url);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (DateTime.now().millisecondsSinceEpoch - (m['t'] as int) >
          _ttl.inMilliseconds) {
        _box!.delete(url);
        return null;
      }
      final data = LinkPreviewData(
        url: url,
        title: m['title'] as String?,
        description: m['description'] as String?,
        imageUrl: m['image'] as String?,
      );
      _cache[url] = data;
      return data;
    } catch (_) {
      _box?.delete(url);
      return null;
    }
  }

  void _writeToDisk(LinkPreviewData d) {
    _box?.put(
      d.url,
      jsonEncode({
        't': DateTime.now().millisecondsSinceEpoch,
        'title': d.title,
        'description': d.description,
        'image': d.imageUrl,
      }),
    );
  }

  static String? extractFirstUrl(String text) => LinkUtils.extractFirstUrl(text);

  bool hasCached(String url) => getCached(url) != null;

  LinkPreviewData? getCached(String url) {
    if (!_enabled) return null;
    return _cache[url] ?? _readFromDisk(url);
  }

  bool _coolingDown(String url) {
    final t = _failedAt[url];
    if (t == null) return false;
    if (DateTime.now().difference(t) < _retryAfter) return true;
    _failedAt.remove(url);
    return false;
  }

  void _markFailed(String url) {
    final now = DateTime.now();
    _failedAt.removeWhere((_, t) => now.difference(t) >= _retryAfter);
    _failedAt[url] = now;
  }

  Future<LinkPreviewData?> fetch(String url) {
    if (!_enabled) return Future.value(null);
    final cached = getCached(url);
    if (cached != null) return Future.value(cached);
    if (_coolingDown(url)) return Future.value(null);
    return _inFlight[url] ??=
        _fetch(url).whenComplete(() => _inFlight.remove(url));
  }

  Future<LinkPreviewData?> _fetch(String url) async {
    try {
      final uri = Uri.parse(url);
      final res = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; Chatme/1.0)',
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 8));

      final contentType = res.headers['content-type'] ?? '';
      debugPrint('[LinkPreview] $url -> status=${res.statusCode} type=$contentType');
      if (res.statusCode != 200 || !contentType.contains('text/html')) {
        _markFailed(url);
        return null;
      }

      final doc = html_parser
          .parse(utf8.decode(res.bodyBytes, allowMalformed: true));

      String? meta(String key) {
        final el = doc.querySelector('meta[property="$key"]') ??
            doc.querySelector('meta[name="$key"]');
        final v = el?.attributes['content']?.trim();
        return (v == null || v.isEmpty) ? null : v;
      }

      final title = meta('og:title') ??
          meta('twitter:title') ??
          doc.querySelector('title')?.text.trim();
      final description = meta('og:description') ??
          meta('twitter:description') ??
          meta('description');
      var image = meta('og:image') ?? meta('twitter:image');
      if (image != null) image = uri.resolve(image).toString();

      final data = LinkPreviewData(
        url: url,
        title: title,
        description: description,
        imageUrl: image,
      );
      if (data.isEmpty) {
        _markFailed(url);
        return null;
      }
      if (!_enabled) return null;

      _failedAt.remove(url);
      _cache[url] = data;
      _writeToDisk(data);
      return data;
    } catch (e) {
      debugPrint('[LinkPreview] $url failed: $e');
      _markFailed(url);
      return null;
    }
  }
}