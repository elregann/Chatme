// Input resolution for the Discovery address bar.
//
// Chromium's omnibox defaults single words to search and treats URL-looking
// input as a URL. Firefox's URL bar treats a space before the first dot, colon
// or question mark as search and fixes up a missing scheme. Dart's Uri.https
// encodes query parameters, so queries are never built by string concatenation.
// Discovery uses Google for search and allows https navigation only.

const String _searchHost = 'www.google.com';

/// Only https can be loaded by the in-app WebView. An empty host is rejected
/// so a partial URL such as `https://` can never start a navigation.
bool isAllowedBrowserNavigation(Uri uri) {
  return uri.scheme.toLowerCase() == 'https' && uri.host.isNotEmpty;
}

int _firstIndexOfAny(String value, List<String> characters) {
  var result = -1;
  for (final character in characters) {
    final index = value.indexOf(character);
    if (index != -1 && (result == -1 || index < result)) result = index;
  }
  return result;
}

bool _looksLikeUrl(String input) {
  final explicitScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').firstMatch(input);
  if (explicitScheme != null) {
    final parsed = Uri.tryParse(input);
    if (parsed == null) return false;
    final scheme = parsed.scheme.toLowerCase();
    return scheme == 'https' || scheme == 'http';
  }

  // A space before the first URL marker means the user is searching.
  final firstSpace = input.indexOf(RegExp(r'\s'));
  final firstMarker = _firstIndexOfAny(input, ['.', ':', '/', '?', '#']);
  if (firstSpace != -1 && (firstMarker == -1 || firstSpace < firstMarker)) {
    return false;
  }

  return firstMarker != -1;
}

/// Builds a Google search URL with encoded query parameters.
Uri browserSearchUrl(String query) {
  return Uri.https(_searchHost, '/search', {'q': query});
}

/// Turns raw address-bar input into an https URL the WebView may load.
///
/// A bare domain gets `https://`, and an explicit `http://` is upgraded to
/// `https://`. Anything else becomes a Google search, so schemes such as
/// `javascript:` can never be navigated to.
Uri resolveBrowserInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return browserSearchUrl(input);

  if (_looksLikeUrl(input)) {
    final parsed = Uri.tryParse(input);
    if (parsed != null && parsed.hasScheme) {
      final scheme = parsed.scheme.toLowerCase();
      if (scheme == 'https') return parsed;
      if (scheme == 'http') {
        final upgraded = Uri.tryParse(
          input.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://'),
        );
        if (upgraded != null && isAllowedBrowserNavigation(upgraded)) {
          return upgraded;
        }
      }
    } else {
      final withScheme = Uri.tryParse('https://$input');
      if (withScheme != null && isAllowedBrowserNavigation(withScheme)) {
        return withScheme;
      }
    }
  }

  return browserSearchUrl(input);
}
