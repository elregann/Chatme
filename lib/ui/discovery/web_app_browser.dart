// web_app_browser.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/chatme_colors.dart';
import '../../core/utils/browser_input.dart';
import '../../core/utils/debug_logger.dart';
import '../../services/chatme_toast.dart';
import '../../data/discovery_apps.dart';
import '../../widgets/chatme_menu.dart';

/// Extracts a host from a URL. Kept as a small pure helper for URL parsing;
/// the browser subtitle itself now shows the full current URL.
String? browserHostFromUrl(String? url) {
  final host = Uri.tryParse(url ?? '')?.host;
  if (host == null || host.isEmpty) return null;
  return host;
}

/// The small single-line second line under the browser title. It shows the
/// exact URL on screen, not just the host, with a tooltip for addresses that
/// get ellipsized.
class BrowserUrlSubtitle extends StatelessWidget {
  const BrowserUrlSubtitle(this.url, {super.key});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: url,
      child: Text(
        url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          color: ChatmeColors.textSubtle,
        ),
      ),
    );
  }
}

/// Back handling for the in-app browser. WebView history comes first; the
/// route is closed only when there is nothing left to go back to.
enum BrowserBackAction { goBack, close }

/// Resolves a back action from the WebView history probe. A failed probe is
/// treated as empty history so the user can always leave the browser.
Future<BrowserBackAction> resolveBrowserBack(
  Future<bool> Function() canGoBackProbe,
) async {
  try {
    final hasHistory = await canGoBackProbe();
    return hasHistory ? BrowserBackAction.goBack : BrowserBackAction.close;
  } catch (e) {
    DebugLogger.log('[Browser] History check failed | $e', type: 'ERROR');
    return BrowserBackAction.close;
  }
}

/// A minimal in-app browser for curated web apps and search results.
///
/// The page is opened as a normal route, so the user stays inside Chatme and
/// can come back with the standard back button. Only https navigation is
/// allowed; no account or relay state is shared with the page.
class WebAppBrowser extends StatefulWidget {
  const WebAppBrowser({
    super.key,
    required this.initialUrl,
    this.app,
  });

  /// The URL to load. Curated apps pass their homepage; searches pass the
  /// resolved search-engine URL.
  final String initialUrl;

  /// Present for curated apps, absent for free-form searches.
  final DiscoveryApp? app;

  @override
  State<WebAppBrowser> createState() => _WebAppBrowserState();
}

class _WebAppBrowserState extends State<WebAppBrowser> {
  late final WebViewController _controller;

  /// One stable widget instance for the whole life of the page.
  ///
  /// `WebViewWidget` derives its platform-view key from freshly created
  /// creation params on every build. Rebuilding it (for example from an
  /// `onProgress` setState) tears down and recreates the native WebView, which
  /// is what makes scrolling stutter and can abort an in-flight page load.
  late final Widget _webView;

  final ValueNotifier<int> _progress = ValueNotifier<int>(0);
  final ValueNotifier<bool> _loading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _loadFailed = ValueNotifier<bool>(false);
  late final ValueNotifier<String> _currentUrl;

  @override
  void initState() {
    super.initState();
    _currentUrl = ValueNotifier<String>(widget.initialUrl);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ChatmeColors.backgroundPrimary)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return isAllowedBrowserNavigation(uri ?? Uri())
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onProgress: (progress) {
            if (mounted) _progress.value = progress;
          },
          onPageStarted: (url) {
            _updateUrl(url);
            if (!mounted) return;
            _loading.value = true;
            _progress.value = 0;
            _loadFailed.value = false;
          },
          onUrlChange: (change) => _updateUrl(change.url),
          onPageFinished: (url) {
            _updateUrl(url);
            _finishLoading();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != true) return;
            if (mounted) _loadFailed.value = true;
            _finishLoading();
          },
        ),
      );

    _webView = RepaintBoundary(
      child: WebViewWidget(
        key: const ValueKey<String>('chatme-discovery-webview'),
        controller: _controller,
      ),
    );

    _controller.loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  void dispose() {
    _progress.dispose();
    _loading.dispose();
    _loadFailed.dispose();
    _currentUrl.dispose();
    super.dispose();
  }

  void _updateUrl(String? url) {
    if (!mounted || url == null || url.isEmpty || url == _currentUrl.value) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (!isAllowedBrowserNavigation(uri ?? Uri())) return;
    _currentUrl.value = url;
  }

  void _finishLoading() {
    if (!mounted) return;
    _loading.value = false;
    _progress.value = 100;
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(_currentUrl.value) ?? Uri.parse(widget.initialUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ChatmeToast.show('Could not open the browser');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _currentUrl.value));
  }

  Future<void> _handleBack() async {
    final action = await resolveBrowserBack(_controller.canGoBack);
    if (action == BrowserBackAction.close) {
      if (mounted) Navigator.pop(context);
      return;
    }
    try {
      await _controller.goBack();
    } catch (e) {
      DebugLogger.log('[Browser] Go back failed | $e', type: 'ERROR');
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _buildTitle() {
    final app = widget.app;
    final icon = app == null
        ? const Icon(
            Icons.language,
            size: 28,
            color: ChatmeColors.accentPrimary,
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              app.iconAsset,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              cacheWidth: 84,
              cacheHeight: 84,
            ),
          );

    return Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                app?.name ?? 'Browser',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: ChatmeColors.textPrimary,
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: _currentUrl,
                builder: (_, url, __) => BrowserUrlSubtitle(url),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: ChatmeColors.textPrimary, size: 18),
            onPressed: _handleBack,
          ),
          centerTitle: false,
          titleSpacing: 16,
          title: _buildTitle(),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, color: ChatmeColors.textPrimary),
              onPressed: () => _controller.reload(),
            ),
            ChatmeMenuButton<String>(
              icon:
                  const Icon(Icons.more_vert, color: ChatmeColors.textPrimary),
              entries: const [
                ChatmeMenuEntry(
                    value: 'open_browser', label: 'Open in browser'),
                ChatmeMenuEntry(value: 'copy_link', label: 'Copy link'),
              ],
              onSelected: (value) {
                if (value == 'open_browser') _openInBrowser();
                if (value == 'copy_link') _copyLink();
              },
            ),
          ],
          elevation: 0,
        ),
        body: Column(
          children: [
            // The progress strip and the error strip stay in the tree at a fixed
            // slot count. Changing Column's children count would remount the
            // platform view and reset the page mid-scroll.
            SizedBox(
              height: 3,
              child: ValueListenableBuilder<bool>(
                valueListenable: _loading,
                builder: (_, loading, __) => Opacity(
                  opacity: loading ? 1 : 0,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _progress,
                    builder: (_, progress, __) => LinearProgressIndicator(
                      value: progress > 0 ? progress / 100 : null,
                      backgroundColor: ChatmeColors.surfaceRaised,
                      color: ChatmeColors.accentPrimary,
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _loadFailed,
              builder: (_, failed, __) {
                if (!failed) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  color: ChatmeColors.surfaceAction,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 18, color: ChatmeColors.statusWarning),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'This site did not load',
                          style: TextStyle(
                            color: ChatmeColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _openInBrowser,
                        child: const Text('Open in browser'),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(child: _webView),
          ],
        ),
      ),
    );
  }
}
