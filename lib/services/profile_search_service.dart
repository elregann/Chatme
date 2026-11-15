// profile_search_service.dart

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/crypto/nostr_protocol.dart';
import '../core/utils/key_utils.dart';
import 'app_settings.dart';
import 'server_lists.dart';

/// One kind 0 profile returned by a search relay.
class ProfileSearchResult {
  final String pubkey;

  /// The `name` field, empty when the profile does not have one.
  final String name;
  final String? displayName;
  final String? nip05;
  final String? picture;
  final String? about;
  final int createdAt;

  /// The relay that returned the newest copy of this profile.
  final String relay;

  const ProfileSearchResult({
    required this.pubkey,
    required this.name,
    this.displayName,
    this.nip05,
    this.picture,
    this.about,
    required this.createdAt,
    required this.relay,
  });

  /// What to show as the title: name, then display name, then the NIP-05
  /// handle, and finally a short npub.
  String get label {
    final nameText = name.trim();
    if (nameText.isNotEmpty) return nameText;

    final displayText = displayName?.trim() ?? '';
    if (displayText.isNotEmpty) return displayText;

    final handle = nip05?.split('@').first.trim() ?? '';
    if (handle.isNotEmpty) return handle;

    return KeyUtils.formatDisplayName(pubkey);
  }
}

/// A socket to one search relay. Tests replace this with a fake.
abstract class SearchRelayConnection {
  Stream<dynamic> get stream;

  void send(String data);

  Future<void> close();
}

class WebSocketSearchConnection implements SearchRelayConnection {
  final WebSocketChannel _channel;

  WebSocketSearchConnection(Uri uri) : _channel = WebSocketChannel.connect(uri);

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() async {
    try {
      await _channel.sink.close();
    } catch (_) {
      // The relay may already be gone.
    }
  }
}

typedef SearchRelayConnector = SearchRelayConnection Function(Uri uri);

/// Asks the configured search relays for kind 0 profiles matching a query.
///
/// Every query uses its own short lived connections, so results never enter
/// the normal relay subscriptions or the profile cache. Nothing is saved:
/// the caller decides what to keep.
class ProfileSearchService {
  static const Duration defaultTimeout = Duration(seconds: 6);
  static const int defaultLimit = 20;

  /// A guard for accidental very long input; relays ignore huge searches.
  static const int _maxQueryLength = 80;

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  final List<String> Function() _relays;
  final SearchRelayConnector _connect;
  final Duration timeout;
  final int limit;

  final Set<SearchRelayConnection> _open = {};
  void Function()? _abort;
  int _request = 0;

  ProfileSearchService({
    List<String> Function()? relays,
    SearchRelayConnector? connect,
    this.timeout = defaultTimeout,
    int limit = defaultLimit,
  })  : _relays = relays ?? (() => AppSettings.instance.searchRelays),
        _connect = connect ?? _webSocket,
        limit = limit.clamp(1, 50);

  static SearchRelayConnection _webSocket(Uri uri) =>
      WebSocketSearchConnection(uri);

  /// Drops the query that is running, if any. Its results are not returned.
  void cancel() {
    _request++;
    _abort?.call();
    for (final connection in List.of(_open)) {
      _open.remove(connection);
      unawaited(connection.close());
    }
  }

  /// Returns the profiles matching [rawQuery], newest copy per pubkey, best
  /// match first. A query that is an npub or a hex pubkey looks the profile up
  /// by author instead of using full text search. Results that arrive after
  /// [timeout] are dropped, but whatever arrived before is still returned.
  Future<List<ProfileSearchResult>> search(String rawQuery) async {
    var query = rawQuery.trim();
    if (query.length > _maxQueryLength) {
      query = query.substring(0, _maxQueryLength);
    }
    if (query.length < 2) return const [];

    final lowered = query.toLowerCase();
    if (lowered.startsWith('nsec') || lowered.startsWith('nostr:nsec')) {
      return const [];
    }

    final relayUrls = _usableRelays();
    if (relayUrls.isEmpty) return const [];

    final request = ++_request;
    final results = <String, ProfileSearchResult>{};
    // A relay may ignore the limit. Keep memory bounded without dropping a
    // newer copy of a profile that is already here.
    final maxResults = limit * 5;
    final pending = relayUrls.toSet();
    final connections = <SearchRelayConnection>[];
    final finished = Completer<void>();

    void finish(String url) {
      if (!pending.remove(url)) return;
      if (pending.isEmpty && !finished.isCompleted) finished.complete();
    }

    void abort() {
      if (!finished.isCompleted) finished.complete();
    }

    _abort = abort;

    final directPubkey = _pubkeyFrom(query);
    final filter = <String, dynamic>{
      'kinds': const [0],
      if (directPubkey == null) 'search': query,
      if (directPubkey == null) 'limit': limit,
      if (directPubkey != null) 'authors': [directPubkey],
      if (directPubkey != null) 'limit': 1,
    };

    for (final url in relayUrls) {
      final subId = 'chatme_search_${request}_${connections.length}';

      void receive(dynamic data) {
        final message = _decode(data);
        if (message == null || message.length < 2) return;
        if (message[1]?.toString() != subId) return;

        final type = message[0];
        if (type == 'EVENT') {
          if (message.length < 3) return;
          final event = message[2];
          if (event is! Map) return;
          final result = _parseEvent(event, url);
          if (result == null) return;
          final existing = results[result.pubkey];
          if (existing == null) {
            if (results.length >= maxResults) return;
            results[result.pubkey] = result;
          } else if (result.createdAt > existing.createdAt) {
            results[result.pubkey] = result;
          }
          return;
        }
        if (type == 'EOSE' || type == 'CLOSED') finish(url);
      }

      SearchRelayConnection? connection;
      try {
        connection = _connect(Uri.parse(url));
        connections.add(connection);
        _open.add(connection);
        connection.stream.listen(
          receive,
          onError: (_) => finish(url),
          onDone: () => finish(url),
          cancelOnError: false,
        );
        connection.send(jsonEncode(['REQ', subId, filter]));
      } catch (_) {
        if (connection != null) {
          _open.remove(connection);
          unawaited(connection.close());
        }
        finish(url);
      }
    }

    Timer? timer;
    try {
      if (!finished.isCompleted) {
        timer = Timer(timeout, abort);
        await finished.future;
      }
    } finally {
      timer?.cancel();
      // A newer query may have taken over while this one was finishing.
      if (identical(_abort, abort)) _abort = null;
      for (final connection in connections) {
        _open.remove(connection);
        unawaited(connection.close());
      }
    }

    // A newer search, or cancel(), has taken over while this one was running.
    if (request != _request) return const [];

    final matches = results.values.toList()
      ..sort((a, b) {
        final byScore = _score(b, query).compareTo(_score(a, query));
        if (byScore != 0) return byScore;
        final byTime = b.createdAt.compareTo(a.createdAt);
        if (byTime != 0) return byTime;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });

    return matches.take(limit).toList(growable: false);
  }

  List<String> _usableRelays() {
    final urls = <String>[];
    for (final url in _relays()) {
      final normalized = ServerAddress.relay(url);
      if (normalized != null && !urls.contains(normalized)) {
        urls.add(normalized);
      }
    }
    return urls.take(ListLimits.searchMax).toList(growable: false);
  }

  static String? _pubkeyFrom(String query) {
    // Accepts npub, nprofile, nostr:npub and hex, the same forms the add
    // contact screen takes.
    final hex = KeyUtils.normalizeToHex(query).toLowerCase();
    return _hex64.hasMatch(hex) ? hex : null;
  }

  static int _score(ProfileSearchResult result, String query) {
    final needle = query.toLowerCase();
    for (final value in [result.name, result.displayName]) {
      final text = value?.trim().toLowerCase() ?? '';
      if (text.isEmpty) continue;
      if (text == needle) return 3;
      if (text.startsWith(needle)) return 2;
      if (text.contains(needle)) return 1;
    }
    return 0;
  }

  static List<dynamic>? _decode(dynamic data) {
    try {
      final decoded = data is String
          ? jsonDecode(data)
          : jsonDecode(utf8.decode(data as List<int>));
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Verifies the event and reads the profile. Anything malformed or not
  /// signed by the pubkey it names is ignored.
  static ProfileSearchResult? _parseEvent(Map event, String relay) {
    if (event['kind'] != 0) return null;

    final pubkey = event['pubkey'];
    final signature = event['sig'];
    final id = event['id'];
    final createdAt = event['created_at'];
    final content = event['content'];
    final tags = event['tags'];
    if (pubkey is! String ||
        signature is! String ||
        id is! String ||
        createdAt is! int ||
        content is! String ||
        tags is! List) {
      return null;
    }
    if (!_hex64.hasMatch(pubkey) ||
        !_hex64.hasMatch(id) ||
        signature.length != 128) {
      return null;
    }

    try {
      final expectedId = NostrSigner.calculateEventId({
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': 0,
        'tags': tags,
        'content': content,
      });
      if (expectedId != id) return null;
      if (!NostrSigner.verify(id, signature, pubkey)) return null;
    } catch (_) {
      return null;
    }

    if (content.trim().isEmpty) return null;
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    return ProfileSearchResult(
      pubkey: pubkey,
      name: _text(decoded['name']) ?? '',
      displayName: _text(decoded['display_name']),
      nip05: _text(decoded['nip05']),
      picture: _text(decoded['picture']),
      about: _text(decoded['about']),
      createdAt: createdAt,
      relay: relay,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
