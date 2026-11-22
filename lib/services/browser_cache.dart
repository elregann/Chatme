// browser_cache.dart

import 'package:webview_flutter/webview_flutter.dart';

/// Clears the data left behind by the in-app WebView.
///
/// Logout and the Discovery overflow menu share this one implementation so
/// cookies, cache and local storage can never drift apart.
class BrowserCache {
  BrowserCache._();

  /// Test seam: widget tests replace this instead of starting a native WebView.
  static Future<void> Function() clear = _clear;

  static Future<void> _clear() async {
    await WebViewCookieManager().clearCookies();
    final controller = WebViewController();
    await controller.clearCache();
    await controller.clearLocalStorage();
  }
}
