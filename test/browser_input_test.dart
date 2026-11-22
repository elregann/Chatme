// Tests for the Discovery address bar input resolver.
//
// References:
// - Chromium omnibox: single words default to search, inputs that look like a
//   URL are treated as URLs.
//   https://chromium.org/user-experience/omnibox
// - Firefox URL bar: a space before the first dot/colon/question mark means
//   search; a missing scheme is fixed up.
//   https://wiki.mozilla.org/Firefox/URL_Bar_Algorithm
// - Dart Uri.https encodes query parameters instead of string concatenation.
//   https://api.dart.dev/dart-core/Uri/Uri.https.html
// - webview_flutter NavigationDelegate.onNavigationRequest is the seam for
//   accepting or rejecting navigation.
//   https://pub.dev/documentation/webview_flutter/latest/webview_flutter/NavigationDelegate-class.html

import 'package:chatme/core/utils/browser_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('browser input resolution', () {
    test('adds https to a bare domain', () {
      expect(
        resolveBrowserInput('primal.net').toString(),
        'https://primal.net',
      );
    });

    test('keeps an explicit https URL intact', () {
      expect(
        resolveBrowserInput('https://example.com/a?b=1').toString(),
        'https://example.com/a?b=1',
      );
    });

    test('upgrades an explicit http URL to https', () {
      expect(
        resolveBrowserInput('http://example.com/a?b=1').toString(),
        'https://example.com/a?b=1',
      );
    });

    test('treats multiple words as a Google search query', () {
      expect(
        resolveBrowserInput('nostr fire').toString(),
        'https://www.google.com/search?q=nostr+fire',
      );
    });

    test('treats a single word as a Google search query', () {
      expect(
        resolveBrowserInput('nostr').toString(),
        'https://www.google.com/search?q=nostr',
      );
    });

    test('encodes reserved characters in the query', () {
      expect(
        resolveBrowserInput('nostr & chatme').toString(),
        'https://www.google.com/search?q=nostr+%26+chatme',
      );
    });

    test('only allows https navigation', () {
      final resolved = resolveBrowserInput('javascript:alert');

      expect(
        resolved.toString(),
        'https://www.google.com/search?q=javascript%3Aalert',
      );
      expect(isAllowedBrowserNavigation(resolved), isTrue);
      expect(
        isAllowedBrowserNavigation(Uri.parse('https://example.com')),
        isTrue,
      );
      expect(
        isAllowedBrowserNavigation(Uri.parse('http://example.com')),
        isFalse,
      );
      expect(
        isAllowedBrowserNavigation(Uri.parse('javascript:alert')),
        isFalse,
      );
      expect(
        isAllowedBrowserNavigation(Uri.parse('file:///etc/passwd')),
        isFalse,
      );
      expect(
        isAllowedBrowserNavigation(Uri.parse('data:text/html,x')),
        isFalse,
      );
      expect(isAllowedBrowserNavigation(Uri.parse('https://')), isFalse);
    });
  });
}
