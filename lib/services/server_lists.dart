// server_lists.dart

/// Built in relays. The two lists never share a relay.
class RelayDefaults {
  RelayDefaults._();

  /// Where others deliver messages to us, announced as our NIP-17 kind 10050.
  static const List<String> inbox = [
    'wss://auth.nostr1.com',
    'wss://nos.lol',
  ];

  /// Extra connections for profiles and more routes.
  static const List<String> other = [
    'wss://messaging.coracle.social',
    'wss://relay.damus.io',
    'wss://relay.primal.net',
  ];
}

class ListLimits {
  ListLimits._();

  static const int inboxMin = 1;

  /// NIP-17 advises one to three inbox relays. More is allowed up to
  /// [inboxMax], with a warning in the screen.
  static const int inboxRecommended = 3;
  static const int inboxMax = 5;
  static const int otherMax = 8;
  static const int blossomMax = 5;
}

enum ListChange { ok, invalid, duplicate, full, missing, tooFew }

class ListEdit {
  final ListChange change;

  /// The new list, or the old one when nothing changed.
  final List<String> list;

  const ListEdit(this.change, this.list);

  bool get ok => change == ListChange.ok;
}

class ServerLists {
  ServerLists._();

  static ListEdit add(
    List<String> list,
    String input, {
    required String? Function(String) normalize,
    required int max,
    Iterable<String> taken = const [],
  }) {
    final url = normalize(input);
    if (url == null) return ListEdit(ListChange.invalid, list);
    if (list.contains(url) || taken.contains(url)) return ListEdit(ListChange.duplicate, list);
    if (list.length >= max) return ListEdit(ListChange.full, list);
    return ListEdit(ListChange.ok, [...list, url]);
  }

  static ListEdit remove(List<String> list, String url, {int minimum = 0}) {
    if (!list.contains(url)) return ListEdit(ListChange.missing, list);
    if (list.length <= minimum) return ListEdit(ListChange.tooFew, list);
    return ListEdit(ListChange.ok, list.where((e) => e != url).toList());
  }

  static bool isDefault(String url, List<String> defaults) => defaults.contains(url);
}

class ServerAddress {
  ServerAddress._();

  static const int _maxLength = 200;
  static final RegExp _label = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');
  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static const List<String> _privateEndings = [
    '.localhost',
    '.local',
    '.internal',
    '.lan',
    '.home.arpa',
  ];

  /// A relay address in normal form (wss only), or null when it is not usable.
  static String? relay(String input) => _normalize(input, 'wss');

  /// A file server address in normal form (https only), or null.
  static String? blossom(String input) => _normalize(input, 'https');

  /// "wss://relay.damus.io" shown as "relay.damus.io".
  static String displayHost(String url) {
    var text = url.replaceFirst(RegExp(r'^[a-z]+://'), '');
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  static String? _normalize(String input, String scheme) {
    var text = input.trim();
    if (text.isEmpty || text.length > _maxLength || text.contains(RegExp(r'\s'))) return null;
    if (!text.contains('://')) text = '$scheme://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.toLowerCase() != scheme) return null;
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;

    final host = uri.host.toLowerCase();
    if (!_isPublicHost(host)) return null;

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '$scheme://$host$port$path';
  }

  static bool _isPublicHost(String host) {
    if (host.isEmpty || host.length > 253) return false;
    if (host.contains(':') || _ipv4.hasMatch(host)) return false;
    if (host == 'localhost') return false;
    if (_privateEndings.any(host.endsWith)) return false;

    final labels = host.split('.');
    if (labels.length < 2) return false;
    if (!labels.every(_label.hasMatch)) return false;
    return RegExp(r'[a-z]').hasMatch(labels.last);
  }
}
