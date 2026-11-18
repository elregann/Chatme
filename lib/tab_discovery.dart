// tab_discovery.dart

import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import 'core/theme/chatme_colors.dart';
import 'data/discovery_apps.dart';
import 'ui/discovery/web_app_browser.dart';

/// The Discovery tab: a flat, curated directory of Nostr web apps.
///
/// Logos are bundled locally, so every row has a real icon without depending
/// on a remote favicon service. The only network use is the web app itself,
/// which is opened inside [WebAppBrowser].
class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key, this.onOpen});

  /// Test seam. In the app, a tap pushes [WebAppBrowser] so the web app stays
  /// inside Chatme instead of opening an external browser.
  final ValueChanged<DiscoveryApp>? onOpen;

  void _open(BuildContext context, DiscoveryApp app) {
    final handler = onOpen;
    if (handler != null) {
      handler(app);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => WebAppBrowser(app: app)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        elevation: 0,
      ),
      body: ListView.separated(
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
      onTap: () => _open(context, app),
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
