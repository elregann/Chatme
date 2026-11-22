// tab_discovery.dart

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import 'core/theme/chatme_colors.dart';
import 'core/utils/browser_input.dart';
import 'core/utils/debug_logger.dart';
import 'data/discovery_apps.dart';
import 'services/browser_cache.dart';
import 'ui/discovery/web_app_browser.dart';
import 'widgets/chatme_menu.dart';
import 'widgets/chatme_search_bar.dart';

/// The Discovery tab: a curated Nostr app directory plus an address bar.
///
/// Logos are bundled locally, so every row has a real icon without depending
/// on a remote favicon service. Typing a bare domain opens it over https, an
/// explicit http URL is upgraded to https, and anything else becomes a Google
/// search. Pages open inside [WebAppBrowser], not in an external browser.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({
    super.key,
    this.onOpen,
    this.onOpenUrl,
  });

  /// Test seam for curated app taps.
  final ValueChanged<DiscoveryApp>? onOpen;

  /// Test seam for address-bar navigation.
  final ValueChanged<String>? onOpenUrl;

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _clearing = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openApp(BuildContext context, DiscoveryApp app) {
    final handler = widget.onOpen;
    if (handler != null) {
      handler(app);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebAppBrowser(initialUrl: app.url, app: app),
      ),
    );
  }

  void _openUrl(String url) {
    final handler = widget.onOpenUrl;
    if (handler != null) {
      handler(url);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WebAppBrowser(initialUrl: url)),
    );
  }

  void _submit(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return;
    _searchFocusNode.unfocus();
    final uri = resolveBrowserInput(input);
    _openUrl(uri.toString());
  }

  Future<void> _clearBrowserData() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      await BrowserCache.clear();
    } catch (e) {
      DebugLogger.log('[Discovery] Clear browser data failed | $e',
          type: 'ERROR');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Widget _buildEngineLogo() {
    return const Icon(
      Remix.google_fill,
      size: 22,
      color: ChatmeColors.accentPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 16,
          title: Text(
            'Discovery',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: Theme.of(context).iconTheme.color,
            ),
          ),
          actions: [
            ChatmeMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: Theme.of(context).iconTheme.color,
              ),
              entries: const [
                ChatmeMenuEntry(
                  value: 'clear_browser_data',
                  label: 'Clear cache',
                ),
              ],
              onSelected: (value) {
                if (value == 'clear_browser_data') _clearBrowserData();
              },
            ),
          ],
          elevation: 0,
        ),
        body: Column(
          children: [
            ChatmeSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              hintText: 'Search or enter URL',
              leading: _buildEngineLogo(),
              onChanged: (_) {},
              onClear: () {},
              onSubmitted: _submit,
            ),
            Expanded(
              child: ListView.separated(
                itemCount: discoveryApps.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 72,
                  endIndent: 16,
                  color: ChatmeColors.surfaceRaised,
                ),
                itemBuilder: (context, index) =>
                    _buildAppRow(context, discoveryApps[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppRow(BuildContext context, DiscoveryApp app) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ChatmeColors.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ChatmeColors.surfaceOverlay),
        ),
        child: Image.asset(
          app.iconAsset,
          fit: BoxFit.cover,
          cacheWidth: 132,
          cacheHeight: 132,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        ),
      ),
      title: Text(
        app.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ChatmeColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        app.description,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ChatmeColors.textMuted,
          fontSize: 13,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: ChatmeColors.textSubtle,
      ),
      onTap: () => _openApp(context, app),
    );
  }

  Widget _fallbackIcon() {
    return const ColoredBox(
      color: ChatmeColors.surfaceRaised,
      child: Center(
        child: Icon(
          Remix.global_line,
          size: 22,
          color: ChatmeColors.accentStrong,
        ),
      ),
    );
  }
}
