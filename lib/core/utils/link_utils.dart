class LinkUtils {
  LinkUtils._();

  static final RegExp _linkRegex = RegExp(
    r'(?:https?://|(?<![A-Za-z0-9@./-])www\.)[^\s<>()]+',
    caseSensitive: false,
  );

  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?]+$');

  /// First real link in [text]: it must start with http://, https:// or
  /// www. and have a host with a dot. www. links are returned as https://.
  static String? extractFirstUrl(String text) {
    for (final match in _linkRegex.allMatches(text)) {
      var raw = match.group(0)!.replaceAll(_trailingPunctuation, '');
      if (raw.toLowerCase().startsWith('www.')) raw = 'https://$raw';

      final uri = Uri.tryParse(raw);
      if (uri == null || !uri.hasAuthority) continue;

      final host = uri.host;
      final bare = host.toLowerCase().startsWith('www.') ? host.substring(4) : host;
      if (!bare.contains('.') || bare.startsWith('.') || bare.endsWith('.')) {
        continue;
      }
      return raw;
    }
    return null;
  }
}
