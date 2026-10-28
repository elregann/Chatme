// link_preview_card.dart

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/link_preview_service.dart';

class LinkPreviewCard extends StatefulWidget {
  final String url;
  final Color textColor;
  final Color backgroundColor;

  const LinkPreviewCard({
    super.key,
    required this.url,
    required this.textColor,
    required this.backgroundColor,
  });

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  LinkPreviewData? _data;

  @override
  void initState() {
    super.initState();
    final service = LinkPreviewService.instance;
    if (service.hasCached(widget.url)) {
      _data = service.getCached(widget.url);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final data = await LinkPreviewService.instance.fetch(widget.url);
    if (mounted && data != null) setState(() => _data = data);
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    final width =
    (MediaQuery.of(context).size.width * 0.9 - 80).clamp(200.0, 300.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: _open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: width,
            color: widget.backgroundColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data.imageUrl != null)
                  CachedNetworkImage(
                    imageUrl: data.imageUrl!,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.title != null)
                        Text(
                          data.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (data.description != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            data.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.textColor.withAlpha(180),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (data.host.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            data.host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.textColor.withAlpha(130),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}