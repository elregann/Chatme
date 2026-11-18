// web_app_browser.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/chatme_colors.dart';
import '../../data/discovery_apps.dart';
import '../../widgets/chatme_menu.dart';

/// A minimal in-app browser for the web apps listed in Discovery.
///
/// The page is opened as a normal route, so the user stays inside Chatme and
/// can come back with the standard back button. No account or relay state is
/// shared with the page: this is only a plain web view.
class WebAppBrowser extends StatefulWidget {
  const WebAppBrowser({super.key, required this.app});

  final DiscoveryApp app;

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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ChatmeColors.backgroundPrimary)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) _progress.value = progress;
          },
          onPageStarted: (_) {
            if (!mounted) return;
            _loading.value = true;
            _progress.value = 0;
            _loadFailed.value = false;
          },
          onPageFinished: (_) => _finishLoading(),
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

    _controller.loadRequest(Uri.parse(widget.app.url));
  }

  @override
  void dispose() {
    _progress.dispose();
    _loading.dispose();
    _loadFailed.dispose();
    super.dispose();
  }

  void _finishLoading() {
    if (!mounted) return;
    _loading.value = false;
    _progress.value = 100;
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.app.url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the browser')),
      );
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.app.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                widget.app.iconAsset,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                cacheWidth: 84,
                cacheHeight: 84,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: ChatmeColors.textPrimary,
                    ),
                  ),
                  Text(
                    widget.app.host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: ChatmeColors.textSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: ChatmeColors.textPrimary),
            onPressed: () => _controller.reload(),
          ),
          ChatmeMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                color: ChatmeColors.textPrimary),
            entries: const [
              ChatmeMenuEntry(value: 'open_browser', label: 'Open in browser'),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    );
  }
}
