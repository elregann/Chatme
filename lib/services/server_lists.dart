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
  static const int blossomMin = 1;
  static const int blossomMax = 5;
}

/// Built in file servers (Blossom), tried from top to bottom.
class BlossomDefaults {
  BlossomDefaults._();

  static const List<String> servers = [
    'https://blossom.ditto.pub',
    'https://nostr.download',
  ];
}

enum RelayGroup { inbox, other }

enum ListChange { ok, invalid, duplicate, full, missing, tooFew, unreachable }

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

/// The two relay lists as the user has them.
class RelayLists {
  final List<String> inbox;
  final List<String> other;

  const RelayLists({required this.inbox, required this.other});

  factory RelayLists.defaults() => const RelayLists(
        inbox: RelayDefaults.inbox,
        other: RelayDefaults.other,
      );

  /// Every relay Chatme connects to, inbox relays first.
  List<String> get all => [...inbox, ...other];

  /// Rebuilds the lists from what was saved, which may be missing or damaged.
  /// Nothing saved gives the defaults. The inbox list is never empty, the
  /// other list may be, and a relay is never in both.
  factory RelayLists.fromStored(Object? rawInbox, Object? rawOther) {
    var inbox = _clean(rawInbox, RelayDefaults.inbox, ListLimits.inboxMax);
    if (inbox.isEmpty) inbox = List.of(RelayDefaults.inbox);

    final other = _clean(rawOther, RelayDefaults.other, ListLimits.otherMax)
        .where((url) => !inbox.contains(url))
        .toList();
    return RelayLists(inbox: inbox, other: other);
  }

  static List<String> _clean(Object? raw, List<String> fallback, int max) {
    if (raw is! List) return List.of(fallback);
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final url = ServerAddress.relay(item);
      if (url != null) seen.add(url);
    }
    return seen.take(max).toList();
  }
}

/// The file server list as the user has it.
class BlossomLists {
  BlossomLists._();

  /// Rebuilds the list from what was saved, which may be missing or damaged.
  /// It is never empty: nothing usable gives the defaults.
  static List<String> fromStored(Object? raw) {
    if (raw is! List) return List.of(BlossomDefaults.servers);
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final url = ServerAddress.blossom(item);
      if (url != null) seen.add(url);
    }
    final list = seen.take(ListLimits.blossomMax).toList();
    return list.isEmpty ? List.of(BlossomDefaults.servers) : list;
  }
}

/// What has to change in the open connections when the lists change.
class RelayDiff {
  final List<String> added;
  final List<String> removed;

  const RelayDiff(this.added, this.removed);

  bool get isEmpty => added.isEmpty && removed.isEmpty;

  factory RelayDiff.between(List<String> before, List<String> after) {
    return RelayDiff(
      after.where((url) => !before.contains(url)).toList(),
      before.where((url) => !after.contains(url)).toList(),
    );
  }
}

/// What to tell the person when a list change is refused. Empty when it worked.
String changeMessage(ListChange change, {required bool fileServer}) {
  switch (change) {
    case ListChange.ok:
      return '';
    case ListChange.invalid:
      return fileServer
          ? 'Enter a server address that starts with https://'
          : 'Enter a relay address that starts with wss://';
    case ListChange.duplicate:
      return 'This one is already in your lists';
    case ListChange.full:
      return 'You have reached the limit for this list';
    case ListChange.missing:
      return 'This one is not in the list';
    case ListChange.unreachable:
      return 'This server did not take a test file. Check the address and try again';
    case ListChange.tooFew:
      return fileServer ? 'Keep at least one file server' : 'Keep at least one inbox relay';
  }
}
